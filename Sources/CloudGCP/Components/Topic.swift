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
                    (.seconds(600)...Duration.seconds(2_678_400)).contains(messageRetention),
                    "messageRetention must be between 10 minutes and 31 days"
                )
            }

            topic = Resource(
                name: name,
                type: "gcp:pubsub:Topic",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(context.gcpStage, name, maxLength: 255),
                    "messageRetentionDuration": messageRetention.map {
                        $0.protobufString
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
        _ = publishingGrant(member: member, bindingName: bindingName)
        return self
    }

    private func publishingGrant(
        member: any Input<String>,
        bindingName: String
    ) -> Resource {
        Resource(
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
    }
}

extension GCP.Topic: GCPLinkable {
    public func grantAccess(to serviceAccount: GCP.ServiceAccount) {
        _ = accessGrants(to: serviceAccount)
    }

    public var actions: [String] {
        [GCP.IAMRole.pubSubPublisher.rawValue]
    }

    public var resources: [Output<String>] {
        [topic.id]
    }

    public var properties: LinkProperties? {
        .init(
            type: "topic",
            name: topic.chosenName,
            properties: [
                "name": name,
                "id": id,
            ]
        )
    }

    public func accessGrants(to serviceAccount: GCP.ServiceAccount) -> [any ResourceProvider] {
        [
            publishingGrant(
                member: serviceAccount.member,
                bindingName: serviceAccount.resource.chosenName
            )
        ]
    }
}
