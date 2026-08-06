import Foundation
import Testing

@testable import CloudCore
@testable import CloudGCP

@Suite("GCP gateway and eventing")
struct GatewayAndEventingTests {
    @Test("API Gateway encodes OpenAPI contents and configures authenticated Cloud Run access")
    func apiGateway() throws {
        let context = makeContext()
        let gatewayIdentity = GCP.ServiceAccount("gateway-identity", context: context)
        let service = GCP.CloudRunService(
            "api",
            image: "us-docker.pkg.dev/example/api:latest",
            context: context
        )
        let gateway = GCP.APIGateway(
            "public-api",
            document: .openAPI(contents: "openapi: 3.0.0"),
            serviceAccount: gatewayIdentity,
            backends: [service],
            context: context
        )

        #expect(gateway.url.description == "https://${testing-public-api.defaultHostname}")
        let configuration = try properties(type: "gcp:apigateway:ApiConfig", in: context)
        #expect(configuration["api"] as? String == "${testing-public-api-api.apiId}")
        let documents = try #require(configuration["openapiDocuments"] as? [[String: Any]])
        let document = try #require(documents.first?["document"] as? [String: Any])
        #expect(document["path"] as? String == "openapi.yaml")
        #expect(document["contents"] as? String == Data("openapi: 3.0.0".utf8).base64EncodedString())

        let tokenCreator = try properties(type: "gcp:serviceaccount:IAMMember", in: context)
        #expect(tokenCreator["role"] as? String == "roles/iam.serviceAccountTokenCreator")
        #expect(context.store.resources.contains { $0.type == "gcp:cloudrunv2:ServiceIamMember" })
        #expect(context.store.resources.contains { $0.type == "gcp:projects:ServiceIdentity" })
    }

    @Test("API Gateway encodes gRPC descriptors and managed service configuration")
    func grpcAPIGateway() throws {
        let context = makeContext()
        let gatewayIdentity = GCP.ServiceAccount("grpc-gateway", context: context)
        let descriptor = Data([0x0A, 0x03, 0x61, 0x70, 0x69])
        let serviceConfiguration = "type: google.api.Service\nname: api.example.com"
        _ = GCP.APIGateway(
            "grpc-api",
            document: .grpc(
                fileDescriptorSet: descriptor,
                serviceConfiguration: serviceConfiguration
            ),
            serviceAccount: gatewayIdentity,
            context: context
        )

        let configuration = try properties(type: "gcp:apigateway:ApiConfig", in: context)
        let services = try #require(configuration["grpcServices"] as? [[String: Any]])
        let descriptorSet = try #require(services.first?["fileDescriptorSet"] as? [String: Any])
        #expect(descriptorSet["path"] as? String == "api_descriptor.pb")
        #expect(descriptorSet["contents"] as? String == descriptor.base64EncodedString())

        let managedConfigurations = try #require(
            configuration["managedServiceConfigs"] as? [[String: Any]]
        )
        let managedConfiguration = try #require(managedConfigurations.first)
        #expect(managedConfiguration["path"] as? String == "api_config.yaml")
        #expect(
            managedConfiguration["contents"] as? String
                == Data(serviceConfiguration.utf8).base64EncodedString()
        )
    }

    @Test("Eventarc and Cloud Tasks authorize their Cloud Run destinations")
    func eventing() throws {
        let context = makeContext()
        let eventIdentity = GCP.ServiceAccount("event-receiver", context: context)
        let taskIdentity = GCP.ServiceAccount("task-dispatcher", context: context)
        let producerIdentity = GCP.ServiceAccount("task-producer", context: context)
        let workflowIdentity = GCP.ServiceAccount("workflow-receiver", context: context)
        let service = GCP.CloudRunService(
            "worker",
            image: "us-docker.pkg.dev/example/worker:latest",
            context: context
        )
        let transport = GCP.Topic("eventarc-transport", context: context)
        _ = GCP.EventarcTrigger(
            "object-created",
            eventType: "google.cloud.storage.object.v1.finalized",
            target: .cloudRun(service, path: "/events"),
            serviceAccount: eventIdentity,
            criteria: [.init(attribute: "bucket", value: "uploads")],
            transportTopic: transport,
            maximumDeliveryAttempts: 1,
            context: context
        )
        _ = GCP.EventarcTrigger(
            "workflow-event",
            eventType: "google.cloud.pubsub.topic.v1.messagePublished",
            target: .workflow("projects/example-project/locations/us-east1/workflows/processor"),
            serviceAccount: workflowIdentity,
            context: context
        )
        _ = GCP.TaskQueue(
            "background",
            rateLimits: .init(
                maximumConcurrentDispatches: 20,
                maximumDispatchesPerSecond: 50
            ),
            retry: .init(maximumAttempts: 8, maximumDoublings: 4),
            target: .cloudRun(service, serviceAccount: taskIdentity),
            loggingSampleRatio: 0.5,
            context: context
        ).allowEnqueuing(from: producerIdentity)

        let trigger = try properties(type: "gcp:eventarc:Trigger", in: context)
        let criteria = try #require(trigger["matchingCriterias"] as? [[String: Any]])
        #expect(criteria.count == 2)
        #expect(criteria.contains { $0["attribute"] as? String == "type" })
        let destination = try #require(trigger["destination"] as? [String: Any])
        let cloudRun = try #require(destination["cloudRunService"] as? [String: Any])
        #expect(cloudRun["path"] as? String == "/events")
        let retryPolicy = try #require(trigger["retryPolicy"] as? [String: Any])
        #expect(retryPolicy["maxAttempts"] as? Int == 1)

        let queue = try properties(type: "gcp:cloudtasks:Queue", in: context)
        let limits = try #require(queue["rateLimits"] as? [String: Any])
        #expect(limits["maxConcurrentDispatches"] as? Int == 20)
        #expect(limits["maxDispatchesPerSecond"] as? Double == 50)
        let target = try #require(queue["httpTarget"] as? [String: Any])
        let token = try #require(target["oidcToken"] as? [String: Any])
        #expect(token["audience"] as? String == "${testing-worker.uri}")

        #expect(context.store.resources.filter { $0.type == "gcp:cloudrunv2:ServiceIamMember" }.count == 2)
        #expect(context.store.resources.contains { $0.type == "gcp:cloudtasks:QueueIamMember" })
        let receiverGrant = try properties(
            type: "gcp:projects:IAMMember",
            in: context,
            chosenName: "event-receiver-service-account-roles-eventarc-event-receiver-project-role"
        )
        #expect(receiverGrant["role"] as? String == "roles/eventarc.eventReceiver")
        #expect(
            context.store.resources.contains {
                $0.type == "gcp:projects:IAMMember"
                    && $0.chosenName.contains("roles-workflows-invoker")
            }
        )
    }

    @Test("Gateways share one API Gateway service agent and version their API config")
    func sharedGatewayIdentity() throws {
        let context = makeContext()
        let backendIdentity = GCP.ServiceAccount("gateway-identity", context: context)
        _ = GCP.APIGateway(
            "public-api",
            document: .openAPI(contents: "openapi: 3.0.0"),
            serviceAccount: backendIdentity,
            context: context
        )
        let admin = GCP.APIGateway(
            "admin-api",
            document: .openAPI(contents: "openapi: 3.0.0\ninfo: {}"),
            serviceAccount: backendIdentity,
            context: context
        )

        // A service agent is project scoped, so both gateways name the same owner.
        let identities = context.store.resources.filter {
            $0.type == "gcp:projects:ServiceIdentity"
        }
        #expect(identities.count == 1)
        #expect(admin.serviceIdentity.resource.chosenName == identities.first?.chosenName)

        // Sharing one backend identity must not duplicate the token creator grant.
        let tokenGrants = context.store.resources.filter {
            $0.type == "gcp:serviceaccount:IAMMember"
        }
        #expect(tokenGrants.count == 1)

        // API configs are immutable, so distinct documents need distinct ids.
        let ids = try context.store.resources
            .filter { $0.type == "gcp:apigateway:ApiConfig" }
            .map { resource -> String in
                let encoded = try JSONEncoder().encode(try #require(resource.properties))
                let object = try #require(
                    JSONSerialization.jsonObject(with: encoded) as? [String: Any]
                )
                return try #require(object["apiConfigId"] as? String)
            }
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
    }

    @Test("Eventarc triggers share one project receiver grant")
    func sharedEventReceiverGrant() throws {
        let context = makeContext()
        let eventIdentity = GCP.ServiceAccount("event-receiver", context: context)
        let service = GCP.CloudRunService(
            "worker",
            image: "us-docker.pkg.dev/example/worker:latest",
            context: context
        )
        for name in ["object-created", "object-deleted"] {
            _ = GCP.EventarcTrigger(
                name,
                eventType: "google.cloud.storage.object.v1.finalized",
                target: .cloudRun(service, path: "/events"),
                serviceAccount: eventIdentity,
                context: context
            )
        }

        // Project IAM is one policy document, so the role needs a single owner.
        let grants = context.store.resources.filter {
            $0.type == "gcp:projects:IAMMember"
                && $0.chosenName.contains("roles-eventarc-event-receiver")
        }
        #expect(grants.count == 1)
    }
}
