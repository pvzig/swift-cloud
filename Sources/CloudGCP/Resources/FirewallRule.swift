import CloudCore

extension GCP {
    /// A stateful VPC firewall rule with explicit allow or deny traffic.
    public struct FirewallRule: GCPResourceProvider {
        public let resource: Resource

        public init(
            _ name: String,
            vpc: VPC,
            direction: Direction = .ingress,
            action: Action,
            sourceRanges: [String] = [],
            destinationRanges: [String] = [],
            sourceServiceAccounts: [any Input<String>] = [],
            targetServiceAccounts: [any Input<String>] = [],
            sourceTags: [String] = [],
            targetTags: [String] = [],
            priority: Int = 1_000,
            logging: Logging = .includeAllMetadata,
            disabled: Bool = false,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            precondition((0...65_535).contains(priority), "priority must be between 0 and 65535")
            action.validate()

            resource = Resource(
                name: name,
                type: "gcp:compute:Firewall",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(context.gcpStage, name),
                    "network": vpc.network.id,
                    "direction": direction.rawValue,
                    "priority": priority,
                    "allows": action.allowProperties,
                    "denies": action.denyProperties,
                    "sourceRanges": sourceRanges,
                    "destinationRanges": destinationRanges,
                    "sourceServiceAccounts": sourceServiceAccounts.map(AnyEncodable.init),
                    "targetServiceAccounts": targetServiceAccounts.map(AnyEncodable.init),
                    "sourceTags": sourceTags,
                    "targetTags": targetTags,
                    "enableLogging": logging.isEnabled,
                    "logConfig": logging.properties,
                    "disabled": disabled,
                ],
                options: options,
                context: context
            )
        }
    }
}

extension GCP.FirewallRule {
    public enum Direction: String, Sendable {
        case egress = "EGRESS"
        case ingress = "INGRESS"
    }

    public enum Action: Sendable {
        case allow([ProtocolRule])
        case deny([ProtocolRule])

        fileprivate var allowProperties: AnyEncodable? {
            guard case .allow(let rules) = self else {
                return nil
            }
            return AnyEncodable(rules.map(\.properties))
        }

        fileprivate var denyProperties: AnyEncodable? {
            guard case .deny(let rules) = self else {
                return nil
            }
            return AnyEncodable(rules.map(\.properties))
        }

        fileprivate func validate() {
            switch self {
            case .allow(let rules), .deny(let rules):
                precondition(rules.isEmpty == false, "firewall actions require at least one protocol rule")
            }
        }
    }

    public struct ProtocolRule: Sendable {
        public let protocolName: String
        public let ports: [String]

        public init(_ protocolName: String, ports: [String] = []) {
            precondition(protocolName.isEmpty == false, "firewall protocols must not be empty")
            self.protocolName = protocolName
            self.ports = ports
        }

        public static func tcp(_ ports: [String] = []) -> Self {
            .init("tcp", ports: ports)
        }

        public static func udp(_ ports: [String] = []) -> Self {
            .init("udp", ports: ports)
        }

        public static let icmp = Self("icmp")

        fileprivate var properties: AnyEncodable {
            [
                "protocol": protocolName,
                "ports": ports,
            ]
        }
    }

    public enum Logging: Sendable {
        case disabled
        case excludeAllMetadata
        case includeAllMetadata

        fileprivate var isEnabled: Bool {
            switch self {
            case .disabled:
                false
            case .excludeAllMetadata, .includeAllMetadata:
                true
            }
        }

        fileprivate var properties: AnyEncodable? {
            switch self {
            case .disabled:
                nil
            case .excludeAllMetadata:
                ["metadata": "EXCLUDE_ALL_METADATA"]
            case .includeAllMetadata:
                ["metadata": "INCLUDE_ALL_METADATA"]
            }
        }
    }
}
