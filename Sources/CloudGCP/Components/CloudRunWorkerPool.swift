import CloudCore

extension GCP {
    /// A continuously running Cloud Run worker pool for pull-based workloads.
    public struct CloudRunWorkerPool: GCPComponent {
        public let workerPool: Resource
        public let serviceAccount: ServiceAccount?
        public let environment: Environment

        public var name: Output<String> {
            workerPool.name
        }

        public init(
            _ name: String,
            image: any Input<String>,
            serviceAccount: ServiceAccount? = nil,
            location: Region? = nil,
            scaling: Scaling = .manual(instanceCount: 1),
            cpu: Int = 1,
            memory: String = "512Mi",
            environment: [String: any Input<String>] = [:],
            secretEnvironment: [CloudRunService.SecretEnvironmentVariable] = [],
            command: [String] = [],
            arguments: [String] = [],
            volumeMounts: [CloudRunService.VolumeMount] = [],
            volumes: [CloudRunService.Volume] = [],
            vpc: VPC? = nil,
            vpcEgress: CloudRunService.VPCEgress = .privateRangesOnly,
            deletionProtection: Bool = false,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            precondition([1, 2, 4, 6, 8].contains(cpu), "cpu must be one of 1, 2, 4, 6, or 8")
            scaling.validate()
            CloudRunService.validateSecretEnvironment(secretEnvironment)

            self.serviceAccount = serviceAccount
            self.environment = Environment(environment, shape: .nameValueList, context: context)

            workerPool = Resource(
                name: name,
                type: "gcp:cloudrunv2:WorkerPool",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(context.gcpStage, name, maxLength: 49),
                    "location": (location ?? context.gcpRegion).rawValue,
                    "deletionProtection": deletionProtection,
                    "scaling": scaling.properties,
                    "template": [
                        "serviceAccount": AnyEncodable(serviceAccount?.email),
                        "containers": [
                            [
                                "name": "worker",
                                "image": image,
                                "commands": command,
                                "args": arguments,
                                "envs": AnyEncodable(
                                    CloudRunEnvironment(
                                        environment: self.environment,
                                        secrets: secretEnvironment
                                    )
                                ),
                                "resources": [
                                    "limits": [
                                        "cpu": "\(cpu)",
                                        "memory": memory,
                                    ]
                                ],
                                "volumeMounts": volumeMounts.map(\.properties),
                            ]
                        ],
                        "volumes": volumes.map(\.properties),
                        "vpcAccess": CloudRunService.vpcAccessProperties(vpc, egress: vpcEgress),
                    ],
                ],
                options: options,
                context: context
            )
        }
    }
}

extension GCP.CloudRunWorkerPool {
    public enum Scaling: Sendable {
        case automatic(minimumInstances: Int = 0, maximumInstances: Int)
        case manual(instanceCount: Int)

        fileprivate var properties: AnyEncodable {
            switch self {
            case .automatic(let minimumInstances, let maximumInstances):
                [
                    "scalingMode": "AUTOMATIC",
                    "minInstanceCount": minimumInstances,
                    "maxInstanceCount": maximumInstances,
                ]
            case .manual(let instanceCount):
                [
                    "scalingMode": "MANUAL",
                    "manualInstanceCount": instanceCount,
                ]
            }
        }

        fileprivate func validate() {
            switch self {
            case .automatic(let minimumInstances, let maximumInstances):
                precondition(minimumInstances >= 0, "minimumInstances must not be negative")
                precondition(maximumInstances >= 1, "maximumInstances must be at least one")
                precondition(
                    minimumInstances <= maximumInstances,
                    "minimumInstances must not exceed maximumInstances"
                )
            case .manual(let instanceCount):
                precondition(instanceCount >= 0, "instanceCount must not be negative")
            }
        }
    }
}

extension GCP.CloudRunWorkerPool: EnvironmentProvider, GCPRoleProvider {
    public var gcpResource: Resource? {
        workerPool
    }

    public var gcpServiceAccount: GCP.ServiceAccount {
        guard let serviceAccount else {
            preconditionFailure("Linking a Cloud Run worker pool requires an explicit service account")
        }
        return serviceAccount
    }

    public var gcpContext: Context {
        workerPool.context
    }
}
