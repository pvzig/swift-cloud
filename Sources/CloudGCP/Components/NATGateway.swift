import CloudCore

extension GCP {
    /// Cloud NAT for outbound internet access from private subnets.
    public struct NATGateway: GCPComponent {
        public let router: Resource
        public let nat: Resource

        public var name: Output<String> {
            nat.name
        }

        public init(
            _ name: String,
            vpc: VPC,
            location: Region? = nil,
            minimumPortsPerVM: Int = 64,
            endpointIndependentMappingEnabled: Bool = true,
            logging: Logging = .errorsOnly,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            precondition(minimumPortsPerVM > 0, "minimumPortsPerVM must be greater than zero")
            let selectedLocation = location ?? vpc.location
            precondition(
                selectedLocation == vpc.location,
                "Cloud NAT must use the VPC subnet's region"
            )
            let region = selectedLocation.rawValue

            router = Resource(
                name: "\(name)-router",
                type: "gcp:compute:Router",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(context.gcpStage, name, "router", maxLength: 63),
                    "network": vpc.network.id,
                    "region": region,
                ],
                options: options,
                context: context
            )

            nat = Resource(
                name: name,
                type: "gcp:compute:RouterNat",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(context.gcpStage, name, maxLength: 63),
                    "router": router.name,
                    "region": region,
                    "natIpAllocateOption": "AUTO_ONLY",
                    "sourceSubnetworkIpRangesToNat": "ALL_SUBNETWORKS_ALL_IP_RANGES",
                    "minPortsPerVm": minimumPortsPerVM,
                    "enableEndpointIndependentMapping": endpointIndependentMappingEnabled,
                    "logConfig": [
                        "enable": logging.isEnabled,
                        "filter": logging.filter,
                    ],
                ],
                options: options,
                context: context,
                dependsOn: [router]
            )
        }
    }
}

extension GCP.NATGateway {
    public enum Logging: Sendable {
        case all
        case disabled
        case errorsOnly
        case translationsOnly

        fileprivate var isEnabled: Bool {
            if case .disabled = self {
                return false
            }
            return true
        }

        fileprivate var filter: String {
            switch self {
            case .all:
                "ALL"
            case .disabled, .errorsOnly:
                "ERRORS_ONLY"
            case .translationsOnly:
                "TRANSLATIONS_ONLY"
            }
        }
    }
}
