import CloudCore

extension GCP {
    public enum Spanner {}
}

extension GCP.Spanner {
    /// A regional or multi-region Spanner instance.
    public struct Instance: GCPResourceProvider {
        public let resource: Resource

        public var name: Output<String> {
            resource.name
        }

        public init(
            _ name: String,
            configuration: String? = nil,
            displayName: String? = nil,
            edition: Edition = .standard,
            capacity: Capacity = .processingUnits(100),
            forceDestroy: Bool = false,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            capacity.validate()
            let resolvedDisplayName =
                displayName
                ?? tokenize(context.gcpStage, name, maxLength: 30)
            precondition(
                (4...30).contains(resolvedDisplayName.count),
                "Spanner display names must contain between 4 and 30 characters"
            )
            resource = Resource(
                name: name,
                type: "gcp:spanner:Instance",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(context.gcpStage, name, maxLength: 30),
                    "config": configuration
                        ?? "regional-\(GCP.resolvedRegion(nil, options: options, context: context).rawValue)",
                    "displayName": resolvedDisplayName,
                    "edition": edition.rawValue,
                    "numNodes": capacity.nodes,
                    "processingUnits": capacity.processingUnits,
                    "autoscalingConfig": capacity.autoscalingProperties,
                    "forceDestroy": forceDestroy,
                ],
                options: options,
                context: context
            )
        }
    }
}

extension GCP.Spanner.Instance {
    public enum Edition: String, Sendable {
        case enterprise = "ENTERPRISE"
        case enterprisePlus = "ENTERPRISE_PLUS"
        case standard = "STANDARD"
    }

    public enum Capacity: Sendable {
        case autoscaling(Autoscaling)
        case nodes(Int)
        case processingUnits(Int)

        fileprivate var nodes: Int? {
            guard case .nodes(let value) = self else {
                return nil
            }
            return value
        }

        fileprivate var processingUnits: Int? {
            guard case .processingUnits(let value) = self else {
                return nil
            }
            return value
        }

        fileprivate var autoscalingProperties: AnyEncodable? {
            guard case .autoscaling(let configuration) = self else {
                return nil
            }
            return configuration.properties
        }

        fileprivate func validate() {
            switch self {
            case .autoscaling(let configuration):
                configuration.validate()
            case .nodes(let value):
                precondition(value > 0, "Spanner node capacity must be greater than zero")
            case .processingUnits(let value):
                Self.validateProcessingUnits(value, name: "Spanner processing units")
            }
        }

        fileprivate static func validateProcessingUnits(_ value: Int, name: String) {
            precondition(value >= 100, "\(name) must be at least 100")
            let increment = value < 1_000 ? 100 : 1_000
            precondition(
                value.isMultiple(of: increment),
                "\(name) must be a multiple of \(increment)"
            )
        }
    }

    public struct Autoscaling: Sendable {
        public let minimumProcessingUnits: Int
        public let maximumProcessingUnits: Int
        public let highPriorityCPUUtilizationPercent: Int
        public let storageUtilizationPercent: Int

        public init(
            minimumProcessingUnits: Int = 100,
            maximumProcessingUnits: Int = 1_000,
            highPriorityCPUUtilizationPercent: Int = 65,
            storageUtilizationPercent: Int = 90
        ) {
            self.minimumProcessingUnits = minimumProcessingUnits
            self.maximumProcessingUnits = maximumProcessingUnits
            self.highPriorityCPUUtilizationPercent = highPriorityCPUUtilizationPercent
            self.storageUtilizationPercent = storageUtilizationPercent
        }

        fileprivate var properties: AnyEncodable {
            [
                "autoscalingLimits": [
                    "minProcessingUnits": minimumProcessingUnits,
                    "maxProcessingUnits": maximumProcessingUnits,
                ],
                "autoscalingTargets": [
                    "highPriorityCpuUtilizationPercent": highPriorityCPUUtilizationPercent,
                    "storageUtilizationPercent": storageUtilizationPercent,
                ],
            ]
        }

        fileprivate func validate() {
            Capacity.validateProcessingUnits(
                minimumProcessingUnits,
                name: "minimumProcessingUnits"
            )
            Capacity.validateProcessingUnits(
                maximumProcessingUnits,
                name: "maximumProcessingUnits"
            )
            precondition(
                maximumProcessingUnits >= minimumProcessingUnits,
                "maximumProcessingUnits must not be less than minimumProcessingUnits"
            )
            precondition(
                (10...90).contains(highPriorityCPUUtilizationPercent),
                "highPriorityCPUUtilizationPercent must be between 10 and 90"
            )
            precondition(
                (10...99).contains(storageUtilizationPercent),
                "storageUtilizationPercent must be between 10 and 99"
            )
        }
    }
}
