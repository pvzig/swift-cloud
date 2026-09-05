import CloudCore

extension GCP {
    public struct Subscription: GCPResourceProvider {
        public let resource: Resource
        public let ordersConsumerAfterAccessGrants: Bool

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
            expiration: Expiration = .never,
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
                    (.seconds(600)...Duration.seconds(2_678_400)).contains(messageRetention),
                    "messageRetention must be between 10 minutes and 31 days"
                )
            }
            expiration.validate(messageRetention: messageRetention)
            switch delivery {
            case .pull:
                ordersConsumerAfterAccessGrants = true
            case .push:
                ordersConsumerAfterAccessGrants = false
            }

            resource = Resource(
                name: name,
                type: "gcp:pubsub:Subscription",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(context.gcpStage, name, maxLength: 255),
                    "topic": topic.name,
                    "ackDeadlineSeconds": acknowledgementSeconds,
                    "pushConfig": delivery.pushProperties,
                    "retryPolicy": retryPolicy?.properties,
                    "deadLetterPolicy": deadLetterPolicy?.properties,
                    "messageRetentionDuration": messageRetention.map {
                        $0.protobufString
                    },
                    "expirationPolicy": expiration.properties,
                ],
                options: options,
                context: context
            )

            if let deadLetterPolicy {
                let pubSubIdentity = ServiceIdentity.shared(
                    .pubSub,
                    options: options,
                    context: context
                )
                _ = deadLetterPolicy.topic.allowPublishing(from: pubSubIdentity)
                _ = allowServiceAgentToConsume(pubSubIdentity)
            }
        }
    }
}

extension GCP.Subscription {
    public enum Expiration: Sendable {
        /// Keeps the infrastructure-managed subscription until the stack deletes it.
        case never
        /// Deletes the subscription after this period without subscriber activity.
        case after(Duration)

        fileprivate var properties: AnyEncodable {
            switch self {
            case .never:
                ["ttl": ""]
            case .after(let duration):
                ["ttl": duration.protobufString]
            }
        }

        fileprivate func validate(messageRetention: Duration?) {
            guard case .after(let duration) = self else {
                return
            }
            precondition(
                duration >= .seconds(86_400),
                "subscription expiration must be at least one day"
            )
            if let messageRetention {
                precondition(
                    duration >= messageRetention,
                    "subscription expiration must not precede message retention"
                )
            }
        }
    }

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
            precondition(
                maximumBackoff <= .seconds(600),
                "maximumBackoff must not exceed 600 seconds"
            )
            self.minimumBackoff = minimumBackoff
            self.maximumBackoff = maximumBackoff
        }

        fileprivate var properties: AnyEncodable {
            [
                "minimumBackoff": minimumBackoff.protobufString,
                "maximumBackoff": maximumBackoff.protobufString,
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
        _ = subscriberGrant(
            member: serviceAccount.member,
            bindingName: serviceAccount.resource.chosenName
        )
        return self
    }

    private func subscriberGrant(
        member: any Input<String>,
        bindingName: String
    ) -> Resource {
        GCP.sharedResource(
            // The identity is part of the name so several subscribers do not
            // collapse into one logical IAM resource.
            name: "\(resource.chosenName)-subscriber-\(bindingName)",
            type: "gcp:pubsub:SubscriptionIAMMember",
            properties: [
                "project": resource.context.gcpProjectID,
                "subscription": name,
                "role": GCP.IAMRole.pubSubSubscriber.rawValue,
                "member": member,
            ],
            options: resource.options,
            context: resource.context
        )
    }

    @discardableResult
    public func allowServiceAgentToConsume(_ serviceIdentity: GCP.ServiceIdentity) -> Self {
        _ = subscriberGrant(
            member: serviceIdentity.member,
            bindingName: serviceIdentity.resource.chosenName
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

    public func accessGrants(to serviceAccount: GCP.ServiceAccount) -> [any ResourceProvider] {
        [
            subscriberGrant(
                member: serviceAccount.member,
                bindingName: serviceAccount.resource.chosenName
            )
        ]
    }
}
