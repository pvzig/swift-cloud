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
        let topic = GCP.Topic(
            "events",
            messageRetention: .seconds(600) + .milliseconds(500),
            context: context
        )
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
            retryPolicy: .init(
                minimumBackoff: .milliseconds(500),
                maximumBackoff: .seconds(600) + .milliseconds(500)
            ),
            deadLetterPolicy: .init(topic: deadLetterTopic),
            messageRetention: .seconds(600) + .milliseconds(500),
            context: context
        ).allowServiceAgentToConsume(pubSubIdentity)

        #expect(subscription.name.description == "${testing-events-push.name}")

        let topicProperties = try properties(
            type: "gcp:pubsub:Topic",
            in: context,
            chosenName: "events"
        )
        #expect(topicProperties["messageRetentionDuration"] as? String == "600.5s")

        let subscriptionProperties = try properties(type: "gcp:pubsub:Subscription", in: context)
        let push = try #require(subscriptionProperties["pushConfig"] as? [String: Any])
        #expect(push["pushEndpoint"] as? String == "${testing-gateway.uri}/v1/events:push")

        let token = try #require(push["oidcToken"] as? [String: Any])
        #expect(token["serviceAccountEmail"] as? String == "${testing-push-service-account.email}")
        #expect(token["audience"] as? String == "${testing-gateway.uri}")

        let retry = try #require(subscriptionProperties["retryPolicy"] as? [String: Any])
        #expect(retry["minimumBackoff"] as? String == "0.5s")
        #expect(retry["maximumBackoff"] as? String == "600.5s")
        #expect(subscriptionProperties["messageRetentionDuration"] as? String == "600.5s")
        let expiration = try #require(subscriptionProperties["expirationPolicy"] as? [String: Any])
        #expect(expiration["ttl"] as? String == "")

        let deadLetter = try #require(subscriptionProperties["deadLetterPolicy"] as? [String: Any])
        #expect(deadLetter["maxDeliveryAttempts"] as? Int == 5)
        #expect(deadLetter["deadLetterTopic"] as? String == "${testing-events-dead-letter.id}")

        #expect(context.store.resources.contains { $0.type == "gcp:serviceaccount:IAMMember" })
        #expect(context.store.resources.contains { $0.type == "gcp:cloudrunv2:ServiceIamMember" })
        #expect(context.store.resources.contains { $0.type == "gcp:pubsub:TopicIAMMember" })
        #expect(context.store.resources.contains { $0.type == "gcp:pubsub:SubscriptionIAMMember" })
    }

    @Test("Subscription expiration can be configured explicitly")
    func subscriptionExpiration() throws {
        let context = makeContext()
        let topic = GCP.Topic("events", context: context)
        _ = GCP.Subscription(
            "short-lived-events",
            topic: topic,
            expiration: .after(.seconds(86_400) + .milliseconds(500)),
            context: context
        )

        let subscription = try properties(type: "gcp:pubsub:Subscription", in: context)
        let expiration = try #require(subscription["expirationPolicy"] as? [String: Any])
        #expect(expiration["ttl"] as? String == "86400.5s")
    }

    @Test("Granting one role to several members keeps every binding")
    func repeatedServiceAccountGrants() throws {
        let context = makeContext()
        let pushAccount = GCP.ServiceAccount("push", context: context)
        let pubSubIdentity = GCP.ServiceIdentity("pubsub-agent", service: .pubSub, context: context)
        let eventarcIdentity = GCP.ServiceIdentity("eventarc-agent", service: .eventarc, context: context)

        pushAccount.grantServiceAccountRole(.serviceAccountTokenCreator, to: pubSubIdentity.member)
        pushAccount.grantServiceAccountRole(.serviceAccountTokenCreator, to: eventarcIdentity.member)
        // The same grant repeated is still a single owner.
        pushAccount.grantServiceAccountRole(.serviceAccountTokenCreator, to: pubSubIdentity.member)

        let grants = context.store.resources.filter { $0.type == "gcp:serviceaccount:IAMMember" }
        #expect(grants.count == 2)
        #expect(Set(grants.map(\.chosenName)).count == 2)

        // Two service agents on one subscription must not collapse either.
        let topic = GCP.Topic("events", context: context)
        _ = GCP.Subscription("events-worker", topic: topic, context: context)
            .allowServiceAgentToConsume(pubSubIdentity)
            .allowServiceAgentToConsume(eventarcIdentity)
        let subscribers = context.store.resources.filter {
            $0.type == "gcp:pubsub:SubscriptionIAMMember"
        }
        #expect(Set(subscribers.map(\.chosenName)).count == 2)
    }

    @Test("Service-account binding names retain colliding normalized members")
    func collisionProofServiceAccountGrants() throws {
        let context = makeContext()
        let serviceAccount = GCP.ServiceAccount("push", context: context)
        let firstMember = "serviceAccount:agent@example.com"
        let secondMember = "service-account-agent-example-com"
        #expect(tokenize(firstMember) == tokenize(secondMember))

        serviceAccount.grantServiceAccountRole(.serviceAccountTokenCreator, to: firstMember)
        serviceAccount.grantServiceAccountRole(.serviceAccountTokenCreator, to: secondMember)

        let grants = context.store.resources.filter {
            $0.type == "gcp:serviceaccount:IAMMember"
        }
        #expect(grants.count == 2)
        #expect(Set(grants.map(\.chosenName)).count == 2)
        let members = try Set(
            grants.map { grant in
                try #require(properties(of: grant)["member"] as? String)
            }
        )
        #expect(members == [firstMember, secondMember])
    }
}
