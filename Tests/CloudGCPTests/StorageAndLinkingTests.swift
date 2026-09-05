import Testing

@testable import CloudCore
@testable import CloudGCP

@Suite("GCP storage and linking")
struct StorageAndLinkingTests {
    @Test("Cloud Run links grant native IAM roles and encode environment metadata")
    func links() throws {
        let context = makeContext()
        let identity = GCP.ServiceAccount("backend", context: context)
        let vpc = GCP.VPC("main", context: context)
        let bucket = GCP.Bucket("assets", versioningEnabled: true, context: context)
        let secret = GCP.Secret("api-key", context: context)
        let topic = GCP.Topic("events", context: context)
        let subscription = GCP.Subscription("events-worker", topic: topic, context: context)
        let database = GCP.SQLDatabase("database", vpc: vpc, context: context)
        let cache = GCP.Cache("cache", vpc: vpc, context: context)
        let service = GCP.CloudRunService(
            "backend",
            image: "us-docker.pkg.dev/example/backend:latest",
            serviceAccount: identity,
            vpc: vpc,
            context: context
        ).link([bucket, secret, topic, subscription, database, cache])

        let serviceProperties = try properties(type: "gcp:cloudrunv2:Service", in: context)
        let template = try #require(serviceProperties["template"] as? [String: Any])
        let containers = try #require(template["containers"] as? [[String: Any]])
        let application = try #require(containers.first)
        let environment = try #require(application["envs"] as? [[String: Any]])

        #expect(environment.contains { $0["name"] as? String == "BUCKET_ASSETS_NAME" })
        #expect(environment.contains { $0["name"] as? String == "SECRET_API_KEY_NAME" })
        #expect(environment.contains { $0["name"] as? String == "TOPIC_EVENTS_ID" })
        #expect(environment.contains { $0["name"] as? String == "SUBSCRIPTION_EVENTS_WORKER_NAME" })
        #expect(environment.contains { $0["name"] as? String == "SQLDB_DATABASE_CONNECTION_NAME" })
        #expect(environment.contains { $0["name"] as? String == "CACHE_CACHE_URL" })

        let types = Set(context.store.resources.map(\.type))
        #expect(types.contains("gcp:storage:BucketIAMMember"))
        #expect(types.contains("gcp:secretmanager:SecretIamMember"))
        #expect(types.contains("gcp:pubsub:TopicIAMMember"))
        #expect(types.contains("gcp:pubsub:SubscriptionIAMMember"))
        #expect(types.contains("gcp:sql:User"))
        #expect(service.environment.values.count >= 13)

        let dependencies = try #require(
            service.service.pulumiProjectResources().values.first?.options?.dependsOn
        )
        let dependencyNames = Set(dependencies.map(\.description))
        let grantTypes: Set = [
            "gcp:storage:BucketIAMMember",
            "gcp:secretmanager:SecretIamMember",
            "gcp:pubsub:TopicIAMMember",
            "gcp:pubsub:SubscriptionIAMMember",
            "gcp:projects:IAMMember",
            "gcp:sql:User",
        ]
        let grants = context.store.resources.filter { grantTypes.contains($0.type) }
        #expect(grants.count == 7)
        for grant in grants {
            #expect(dependencyNames.contains(grant.output.description))
        }
    }

    @Test("Bucket and secret use private-by-default resource settings")
    func privateDefaults() throws {
        let context = makeContext(stage: "production")
        _ = GCP.Bucket("assets", context: context)
        _ = GCP.Secret("api-key", context: context)

        let bucket = try properties(type: "gcp:storage:Bucket", in: context)
        #expect(bucket["uniformBucketLevelAccess"] as? Bool == true)
        #expect(bucket["publicAccessPrevention"] as? String == "enforced")

        let secret = try properties(type: "gcp:secretmanager:Secret", in: context)
        #expect(secret["deletionProtection"] as? Bool == true)
        #expect(secret["replication"] != nil)
    }

    @Test("Direct resource access helpers create their IAM grants")
    func directAccessHelpers() {
        let context = makeContext()
        let identity = GCP.ServiceAccount("worker", context: context)
        let bucket = GCP.Bucket("assets", context: context)
            .allowObjectAccess(from: identity)
        let secret = GCP.Secret("api-key", context: context)
            .allowAccess(from: identity)
        let topic = GCP.Topic("events", context: context)
        let subscription = GCP.Subscription(
            "events-worker",
            topic: topic,
            context: context
        ).allowConsuming(from: identity)

        #expect(bucket.name.description == "${testing-assets.name}")
        #expect(secret.secretID.description == "${testing-api-key.secretId}")
        #expect(subscription.name.description == "${testing-events-worker.name}")
        #expect(
            context.store.resources.filter {
                $0.type == "gcp:storage:BucketIAMMember"
            }.count == 1
        )
        #expect(
            context.store.resources.filter {
                $0.type == "gcp:secretmanager:SecretIamMember"
            }.count == 1
        )
        #expect(
            context.store.resources.filter {
                $0.type == "gcp:pubsub:SubscriptionIAMMember"
            }.count == 1
        )
    }

    @Test("Targeted queues and push subscriptions do not create link dependency cycles")
    func targetLinks() throws {
        let context = makeContext()
        let runtime = GCP.ServiceAccount("backend", context: context)
        let dispatcher = GCP.ServiceAccount("dispatcher", context: context)
        let service = GCP.CloudRunService(
            "backend",
            image: "us-docker.pkg.dev/example/backend:latest",
            serviceAccount: runtime,
            context: context
        )
        let queue = GCP.TaskQueue(
            "jobs",
            target: .cloudRun(service, serviceAccount: dispatcher),
            context: context
        )
        let topic = GCP.Topic("events", context: context)
        let subscription = GCP.Subscription(
            "events-push",
            topic: topic,
            delivery: .push(
                endpoint: service.url,
                serviceAccount: dispatcher,
                audience: service.url
            ),
            context: context
        )

        service.link(queue, subscription)

        let dependencies =
            service.service.pulumiProjectResources()
            .values.first?.options?.dependsOn ?? []
        let names = Set(dependencies.map(\.description))
        #expect(names.contains("${testing-jobs-enqueuer-backend-service-account}") == false)
        #expect(names.contains("${testing-events-push-subscriber-backend-service-account}") == false)
        #expect(context.store.resources.contains { $0.type == "gcp:cloudtasks:QueueIamMember" })
        #expect(context.store.resources.contains { $0.type == "gcp:pubsub:SubscriptionIAMMember" })
    }

    @Test("linkTo grants access and injects environment metadata")
    func reverseLinkSyntax() {
        let context = makeContext()
        let runtime = GCP.ServiceAccount("backend", context: context)
        let service = GCP.CloudRunService(
            "backend",
            image: "us-docker.pkg.dev/example/backend:latest",
            serviceAccount: runtime,
            context: context
        )
        let bucket = GCP.Bucket("assets", context: context).linkTo(service)

        #expect(service.environment.values.keys.contains("BUCKET_ASSETS_NAME"))
        #expect(bucket.name.description == "${testing-assets.name}")
        #expect(context.store.resources.contains { $0.type == "gcp:storage:BucketIAMMember" })
    }
}
