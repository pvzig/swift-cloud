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
}
