import CloudCore

extension GCP {
    public struct Subscription: GCPResourceProvider {
        public let resource: Resource

        public var name: Output<String> {
            resource.name
        }

        public init(
            _ name: String,
            topic: Topic,
            delivery: Delivery = .pull,
            acknowledgementDeadline: Duration = .seconds(10),
            retryPolicy: RetryPolicy? = nil,
            deadLetterPolicy: DeadLetterPolicy? = nil,
            messageRetention: Duration? = nil,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            let acknowledgementSeconds = acknowledgementDeadline.components.seconds
            precondition(
                (10...600).contains(acknowledgementSeconds),
                "acknowledgementDeadline must be between 10 and 600 seconds"
            )
            if let messageRetention {
                precondition(
                    (600...2_678_400).contains(messageRetention.components.seconds),
                    "messageRetention must be between 10 minutes and 31 days"
                )
            }

            resource = Resource(
                name: name,
                type: "gcp:pubsub:Subscription",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(context.gcpStage, name),
                    "topic": topic.name,
                    "ackDeadlineSeconds": acknowledgementSeconds,
                    "pushConfig": delivery.pushProperties,
                    "retryPolicy": retryPolicy?.properties,
                    "deadLetterPolicy": deadLetterPolicy?.properties,
                    "messageRetentionDuration": messageRetention.map {
                        "\($0.components.seconds)s"
                    },
                ],
                options: options,
                context: context
            )
        }
    }
}

extension GCP.Subscription {
    public enum Delivery: Sendable {
        case pull
        case push(
            endpoint: any Input<String>,
            serviceAccount: GCP.ServiceAccount,
            audience: any Input<String>
        )

        fileprivate var pushProperties: AnyEncodable? {
            switch self {
            case .pull:
                nil
            case .push(let endpoint, let serviceAccount, let audience):
                [
                    "pushEndpoint": endpoint,
                    "oidcToken": [
                        "serviceAccountEmail": serviceAccount.email,
                        "audience": audience,
                    ],
                ]
            }
        }
    }

    public struct RetryPolicy: Sendable {
        public let minimumBackoff: Duration
        public let maximumBackoff: Duration

        public init(
            minimumBackoff: Duration = .seconds(10),
            maximumBackoff: Duration = .seconds(600)
        ) {
            precondition(minimumBackoff >= .zero, "minimumBackoff must not be negative")
            precondition(maximumBackoff >= minimumBackoff, "maximumBackoff must not be less than minimumBackoff")
            self.minimumBackoff = minimumBackoff
            self.maximumBackoff = maximumBackoff
        }

        fileprivate var properties: AnyEncodable {
            [
                "minimumBackoff": "\(minimumBackoff.components.seconds)s",
                "maximumBackoff": "\(maximumBackoff.components.seconds)s",
            ]
        }
    }

    public struct DeadLetterPolicy: Sendable {
        public let topic: GCP.Topic
        public let maximumDeliveryAttempts: Int

        public init(topic: GCP.Topic, maximumDeliveryAttempts: Int = 5) {
            precondition(
                (5...100).contains(maximumDeliveryAttempts),
                "maximumDeliveryAttempts must be between 5 and 100"
            )
            self.topic = topic
            self.maximumDeliveryAttempts = maximumDeliveryAttempts
        }

        fileprivate var properties: AnyEncodable {
            [
                "deadLetterTopic": topic.id,
                "maxDeliveryAttempts": maximumDeliveryAttempts,
            ]
        }
    }
}

extension GCP.Subscription {
    @discardableResult
    public func allowConsuming(from serviceAccount: GCP.ServiceAccount) -> Self {
        _ = Resource(
            name: "\(resource.chosenName)-subscriber-\(serviceAccount.resource.chosenName)",
            type: "gcp:pubsub:SubscriptionIAMMember",
            properties: [
                "project": resource.context.gcpProjectID,
                "subscription": name,
                "role": GCP.IAMRole.pubSubSubscriber.rawValue,
                "member": serviceAccount.member,
            ],
            options: resource.options,
            context: resource.context
        )
        return self
    }

    @discardableResult
    public func allowServiceAgentToConsume(_ serviceIdentity: GCP.ServiceIdentity) -> Self {
        _ = Resource(
            // The identity is part of the name so two service agents on one
            // subscription do not collapse into a single logical resource.
            name: "\(resource.chosenName)-subscriber-\(serviceIdentity.resource.chosenName)",
            type: "gcp:pubsub:SubscriptionIAMMember",
            properties: [
                "project": resource.context.gcpProjectID,
                "subscription": name,
                "role": GCP.IAMRole.pubSubSubscriber.rawValue,
                "member": serviceIdentity.member,
            ],
            options: resource.options,
            context: resource.context
        )
        return self
    }
}

extension GCP.Subscription: GCPLinkable {
    public var actions: [String] {
        [GCP.IAMRole.pubSubSubscriber.rawValue]
    }

    public var resources: [Output<String>] {
        [resource.id]
    }

    public var properties: LinkProperties? {
        .init(
            type: "subscription",
            name: resource.chosenName,
            properties: ["name": name]
        )
    }

    public func grantAccess(to serviceAccount: GCP.ServiceAccount) {
        allowConsuming(from: serviceAccount)
    }
}
