import CloudCore

extension GCP {
    public struct Topic: GCPComponent {
        public let topic: Resource

        public var name: Output<String> {
            topic.name
        }

        /// Fully qualified `projects/.../topics/...` identifier.
        public var id: Output<String> {
            topic.id
        }

        public init(
            _ name: String,
            messageRetention: Duration? = nil,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            if let messageRetention {
                precondition(
                    (600...2_678_400).contains(messageRetention.components.seconds),
                    "messageRetention must be between 10 minutes and 31 days"
                )
            }

            topic = Resource(
                name: name,
                type: "gcp:pubsub:Topic",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(context.stage, name),
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

extension GCP.Topic {
    @discardableResult
    public func allowPublishing(from serviceAccount: GCP.ServiceAccount) -> Self {
        allowPublishing(
            member: serviceAccount.member,
            bindingName: serviceAccount.resource.chosenName
        )
    }

    @discardableResult
    public func allowPublishing(from serviceIdentity: GCP.ServiceIdentity) -> Self {
        allowPublishing(
            member: serviceIdentity.member,
            bindingName: serviceIdentity.resource.chosenName
        )
    }

    @discardableResult
    private func allowPublishing(
        member: any Input<String>,
        bindingName: String
    ) -> Self {
        _ = Resource(
            name: "\(topic.chosenName)-publisher-\(bindingName)",
            type: "gcp:pubsub:TopicIAMMember",
            properties: [
                "project": topic.context.gcpProjectID,
                "topic": name,
                "role": GCP.IAMRole.pubSubPublisher.rawValue,
                "member": member,
            ],
            options: topic.options,
            context: topic.context
        )
        return self
    }
}
