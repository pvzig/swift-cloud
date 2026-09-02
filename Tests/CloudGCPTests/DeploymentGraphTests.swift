import Foundation
import Testing

@testable import CloudCore
@testable import CloudGCP

@Suite("GCP deployment graph")
struct DeploymentGraphTests {
    @Test("A production topology encodes without resource-name collisions")
    func productionTopology() throws {
        let context = makeContext(stage: "production")
        let apis: [any ResourceProvider] = [
            GCP.ProjectService(.apiGateway, context: context),
            GCP.ProjectService(.artifactRegistry, context: context),
            GCP.ProjectService(.cloudDNS, context: context),
            GCP.ProjectService(.cloudRun, context: context),
            GCP.ProjectService(.cloudScheduler, context: context),
            GCP.ProjectService(.cloudSQL, context: context),
            GCP.ProjectService(.cloudTasks, context: context),
            GCP.ProjectService(.compute, context: context),
            GCP.ProjectService(.eventarc, context: context),
            GCP.ProjectService(.firestore, context: context),
            GCP.ProjectService(.pubSub, context: context),
            GCP.ProjectService(.redis, context: context),
            GCP.ProjectService(.secretManager, context: context),
            GCP.ProjectService(.serviceNetworking, context: context),
            GCP.ProjectService(.spanner, context: context),
            GCP.ProjectService(.storage, context: context),
        ]
        let options = Resource.Options.dependsOn(apis)
        let identity = GCP.ServiceAccount("backend", options: options, context: context)
        let batchIdentity = GCP.ServiceAccount("batch-worker", options: options, context: context)
        let eventIdentity = GCP.ServiceAccount("event-receiver", options: options, context: context)
        let gatewayIdentity = GCP.ServiceAccount("gateway-identity", options: options, context: context)
        let schedulerIdentity = GCP.ServiceAccount("job-scheduler", options: options, context: context)
        let taskIdentity = GCP.ServiceAccount("task-dispatcher", options: options, context: context)
        let taskProducerIdentity = GCP.ServiceAccount("task-producer", options: options, context: context)
        let workerIdentity = GCP.ServiceAccount("pull-worker", options: options, context: context)
        let vpc = GCP.VPC("main", options: options, context: context)
        let repository = GCP.ArtifactRegistry("services", options: options, context: context)
        let image = GCP.ContainerImage(
            "backend",
            targetName: "ExampleService",
            repository: repository,
            context: context
        )
        let bucket = GCP.Bucket(
            "assets",
            publicReadAccess: true,
            options: options,
            context: context
        )
        let secret = GCP.Secret("api-key", options: options, context: context)
        let database = GCP.SQLDatabase(
            "database",
            availability: .regional,
            vpc: vpc,
            readReplicaCount: 1,
            options: options,
            context: context
        )
        let cache = GCP.Cache("cache", vpc: vpc, options: options, context: context)
        let topic = GCP.Topic("events", options: options, context: context)
        let subscription = GCP.Subscription(
            "events-worker",
            topic: topic,
            options: options,
            context: context
        )
        let firestore = GCP.FirestoreDatabase(
            "documents",
            indexes: [
                .init(
                    collection: "events",
                    fields: [.ascending("tenantID"), .descending("createdAt")]
                )
            ],
            options: options,
            context: context
        )
        let spannerInstance = GCP.Spanner.Instance(
            "global-data",
            capacity: .autoscaling(.init()),
            options: options,
            context: context
        )
        let spanner = GCP.Spanner.Database(
            "accounts",
            instance: spannerInstance,
            schema: ["CREATE TABLE Accounts (AccountId STRING(36) NOT NULL) PRIMARY KEY (AccountId)"],
            options: options,
            context: context
        )
        let service = GCP.CloudRunService(
            "backend",
            image: image.reference,
            serviceAccount: identity,
            ingress: .internalLoadBalancer,
            vpc: vpc,
            options: options,
            context: context
        ).link([bucket, secret, database, cache, topic, subscription, firestore, spanner])
        let batchJob = GCP.CloudRunJob(
            "batch",
            image: image.reference,
            serviceAccount: batchIdentity,
            vpc: vpc,
            options: options,
            context: context
        ).link([bucket, secret, firestore])
        _ = GCP.CloudRunWorkerPool(
            "pull-worker",
            image: image.reference,
            serviceAccount: workerIdentity,
            scaling: .automatic(maximumInstances: 10),
            vpc: vpc,
            options: options,
            context: context
        ).link(subscription)
        _ = GCP.SchedulerJob(
            "backend-tick",
            schedule: "*/5 * * * *",
            target: .cloudRun(service, serviceAccount: identity),
            options: options,
            context: context
        )
        _ = GCP.SchedulerJob(
            "batch-nightly",
            schedule: "0 2 * * *",
            target: .cloudRunJob(batchJob, serviceAccount: schedulerIdentity),
            options: options,
            context: context
        )
        _ = GCP.EventarcTrigger(
            "asset-created",
            eventType: "google.cloud.storage.object.v1.finalized",
            target: .cloudRun(service, path: "/events/storage"),
            serviceAccount: eventIdentity,
            criteria: [.init(attribute: "bucket", value: "assets")],
            options: options,
            context: context
        )
        _ = GCP.TaskQueue(
            "background",
            rateLimits: .init(maximumConcurrentDispatches: 20),
            target: .cloudRun(service, serviceAccount: taskIdentity),
            options: options,
            context: context
        ).allowEnqueuing(from: taskProducerIdentity)
        _ = GCP.APIGateway(
            "public-api",
            document: .openAPI(contents: "openapi: 3.0.0"),
            serviceAccount: gatewayIdentity,
            backends: [service],
            options: options,
            context: context
        )
        _ = GCP.FirewallRule(
            "allow-health-checks",
            vpc: vpc,
            action: .allow([.tcp(["8080"])]),
            sourceRanges: ["35.191.0.0/16", "130.211.0.0/22"],
            options: options,
            context: context
        )
        _ = GCP.NATGateway(
            "outbound",
            vpc: vpc,
            options: options,
            context: context
        )
        let dns = GCP.DNS(
            "example-zone",
            zoneName: "example.com",
            options: options,
            context: context
        )
        _ = GCP.CDN(
            "backend-edge",
            origins: [
                .cloudRun(service, path: "*"),
                .bucket(bucket, path: "/assets/*"),
                .external(hostname: "images.example.net", path: "/images/*"),
            ],
            domainName: .init(hostname: "api.example.com", dns: dns),
            options: options,
            context: context
        )

        _ = GCP.getProject(context: context)
        _ = GCP.Compute.getNetwork(name: "shared", context: context)
        _ = GCP.Compute.getSubnetwork(name: "private", context: context)
        _ = GCP.DNS.getManagedZone(name: "example-zone", context: context)

        let resources = context.store.resources.reduce(into: Pulumi.Project.Resources()) {
            $0.merge($1.pulumiProjectResources()) { _, new in new }
        }
        let encoded = try JSONEncoder().encode(resources)
        #expect(encoded.isEmpty == false)
        #expect(resources.count == context.store.resources.count)
        #expect(resources.count >= 90)
        #expect(context.store.builds.count == 1)
        #expect(context.store.variables.count == 5)
    }
}
