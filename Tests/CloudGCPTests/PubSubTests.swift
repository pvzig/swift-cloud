import Testing

@testable import CloudCore
@testable import CloudGCP

@Suite("GCP Pub/Sub")
struct PubSubTests {
    @Test("Authenticated push subscription includes retry and dead-letter policy")
    func pushSubscription() throws {
        let context = makeContext()
        let pushAccount = GCP.ServiceAccount("push", context: context)
        let pubSubIdentity = GCP.ServiceIdentity("pubsub-agent", service: .pubSub, context: context)
        pushAccount.grantServiceAccountRole(.serviceAccountTokenCreator, to: pubSubIdentity.member)

        let gateway = GCP.CloudRunService(
            "gateway",
            image: "gcr.io/example/gateway:latest",
            context: context
        ).allowInvocation(from: pushAccount)
        let topic = GCP.Topic("events", context: context)
        let deadLetterTopic = GCP.Topic("events-dead-letter", context: context)
            .allowPublishing(from: pubSubIdentity)

        let subscription = GCP.Subscription(
            "events-push",
            topic: topic,
            delivery: .push(
                endpoint: "\(gateway.url)/v1/events:push",
                serviceAccount: pushAccount,
                audience: gateway.url
            ),
            retryPolicy: .init(minimumBackoff: .seconds(10), maximumBackoff: .seconds(600)),
            deadLetterPolicy: .init(topic: deadLetterTopic),
            context: context
        ).allowServiceAgentToConsume(pubSubIdentity)

        #expect(subscription.name.description == "${testing-events-push.name}")

        let subscriptionProperties = try properties(type: "gcp:pubsub:Subscription", in: context)
        let push = try #require(subscriptionProperties["pushConfig"] as? [String: Any])
        #expect(push["pushEndpoint"] as? String == "${testing-gateway.uri}/v1/events:push")

        let token = try #require(push["oidcToken"] as? [String: Any])
        #expect(token["serviceAccountEmail"] as? String == "${testing-push-service-account.email}")
        #expect(token["audience"] as? String == "${testing-gateway.uri}")

        let retry = try #require(subscriptionProperties["retryPolicy"] as? [String: Any])
        #expect(retry["minimumBackoff"] as? String == "10s")
        #expect(retry["maximumBackoff"] as? String == "600s")

        let deadLetter = try #require(subscriptionProperties["deadLetterPolicy"] as? [String: Any])
        #expect(deadLetter["maxDeliveryAttempts"] as? Int == 5)
        #expect(deadLetter["deadLetterTopic"] as? String == "${testing-events-dead-letter.id}")

        #expect(context.store.resources.contains { $0.type == "gcp:serviceaccount:IAMMember" })
        #expect(context.store.resources.contains { $0.type == "gcp:cloudrunv2:ServiceIamMember" })
        #expect(context.store.resources.contains { $0.type == "gcp:pubsub:TopicIAMMember" })
        #expect(context.store.resources.contains { $0.type == "gcp:pubsub:SubscriptionIAMMember" })
    }
}
