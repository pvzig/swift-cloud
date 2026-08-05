import CloudCore

extension GCP {
    /// Routes Google Cloud events to a supported Eventarc destination.
    public struct EventarcTrigger: GCPComponent {
        public let trigger: Resource
        public let eventReceiverGrant: Resource

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
            maximumDeliveryAttempts: Int? = nil,
            location: Region? = nil,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            precondition(eventType.isEmpty == false, "eventType must not be empty")
            if let maximumDeliveryAttempts {
                precondition(
                    maximumDeliveryAttempts == 1,
                    "the GCP provider currently supports only one maximum delivery attempt"
                )
            }

            eventReceiverGrant = Resource(
                name: "\(name)-event-receiver",
                type: "gcp:projects:IAMMember",
                properties: [
                    "project": context.gcpProjectID,
                    "role": GCP.IAMRole.eventarcEventReceiver.rawValue,
                    "member": serviceAccount.member,
                ],
                options: options,
                context: context
            )
            target.grantInvocation(to: serviceAccount)

            let matchingCriteria = [Criterion(attribute: "type", value: eventType)] + criteria
            trigger = Resource(
                name: name,
                type: "gcp:eventarc:Trigger",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(context.stage, name),
                    "location": (location ?? context.gcpRegion).rawValue,
                    "serviceAccount": serviceAccount.email,
                    "eventDataContentType": contentType.rawValue,
                    "matchingCriterias": matchingCriteria.map(\.properties),
                    "destination": target.properties,
                    "transport": transportTopic.map {
                        ["pubsub": ["topic": $0.id]]
                    },
                    "retryPolicy": maximumDeliveryAttempts.map {
                        ["maxAttempts": $0]
                    },
                ],
                options: options,
                context: context,
                dependsOn: [eventReceiverGrant]
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
