import CloudCore

extension GCP {
    /// Routes Google Cloud events to a supported Eventarc destination.
    public struct EventarcTrigger: GCPComponent {
        public let trigger: Resource
        public let eventReceiverGrant: Resource
        public let storagePublisherGrant: Resource?

        public var name: Output<String> {
            trigger.name
        }

        public init(
            _ name: String,
            eventType: String,
            target: Target,
            serviceAccount: ServiceAccount,
            criteria: [Criterion] = [],
            transportTopic: Topic? = nil,
            contentType: ContentType = .json,
            location: Region? = nil,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            precondition(eventType.isEmpty == false, "eventType must not be empty")
            precondition(
                transportTopic == nil || eventType == "google.cloud.pubsub.topic.v1.messagePublished",
                "a custom transport topic requires the Pub/Sub messagePublished event type"
            )
            // Owned by the service account so triggers that share an identity do not
            // declare competing owners for the same project IAM binding.
            eventReceiverGrant = serviceAccount.projectRole(.eventarcEventReceiver)
            target.grantInvocation(to: serviceAccount)
            if eventType.hasPrefix("google.cloud.storage.") {
                let storageIdentity = ServiceIdentity.shared(
                    .storage,
                    options: options,
                    context: context
                )
                storagePublisherGrant = GCP.sharedResource(
                    name: "\(storageIdentity.resource.chosenName)-pubsub-publisher-project-role",
                    type: "gcp:projects:IAMMember",
                    properties: [
                        "project": context.gcpProjectID,
                        "role": GCP.IAMRole.pubSubPublisher.rawValue,
                        "member": storageIdentity.member,
                    ],
                    options: options,
                    context: context
                )
            } else {
                storagePublisherGrant = nil
            }

            let matchingCriteria = [Criterion(attribute: "type", value: eventType)] + criteria
            trigger = Resource(
                name: name,
                type: "gcp:eventarc:Trigger",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(context.gcpStage, name, maxLength: 63),
                    "location": GCP.resolvedRegion(location, options: options, context: context).rawValue,
                    "serviceAccount": serviceAccount.email,
                    "eventDataContentType": contentType.rawValue,
                    "matchingCriterias": matchingCriteria.map(\.properties),
                    "destination": target.properties,
                    "transport": transportTopic.map {
                        ["pubsub": ["topic": $0.id]]
                    },
                ],
                options: options,
                context: context,
                dependsOn: [eventReceiverGrant] + [storagePublisherGrant].compactMap { $0 }
            )
        }
    }
}

extension GCP.EventarcTrigger {
    public enum ContentType: String, Sendable {
        case json = "application/json"
        case protobuf = "application/protobuf"
    }

    public struct Criterion: Sendable {
        public let attribute: String
        public let value: String
        public let operatorName: String?

        public init(attribute: String, value: String, operator operatorName: String? = nil) {
            precondition(attribute.isEmpty == false, "criterion attributes must not be empty")
            precondition(value.isEmpty == false, "criterion values must not be empty")
            self.attribute = attribute
            self.value = value
            self.operatorName = operatorName
        }

        fileprivate var properties: AnyEncodable {
            [
                "attribute": attribute,
                "value": value,
                "operator": operatorName,
            ]
        }
    }

    public enum Target: Sendable {
        case cloudRun(GCP.CloudRunService, path: String = "/")
        case workflow(any Input<String>)

        fileprivate var properties: AnyEncodable {
            switch self {
            case .cloudRun(let service, let path):
                [
                    "cloudRunService": [
                        "service": service.name,
                        "region": service.service.output.keyPath("location"),
                        "path": path,
                    ]
                ]
            case .workflow(let workflow):
                ["workflow": workflow]
            }
        }

        fileprivate func grantInvocation(to serviceAccount: GCP.ServiceAccount) {
            switch self {
            case .cloudRun(let service, _):
                service.allowInvocation(from: serviceAccount)
            case .workflow:
                serviceAccount.grantProjectRole(.workflowsInvoker)
            }
        }
    }
}
