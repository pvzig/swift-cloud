import CloudCore

extension GCP {
    public struct CloudRunService: GCPComponent {
        public let service: Resource
        public let serviceAccount: ServiceAccount?
        public let environment: Environment

        public var name: Output<String> {
            service.name
        }

        public var url: Output<String> {
            service.output.keyPath("uri")
        }

        /// The region this service was deployed to.
        ///
        /// Regional resources that must co-locate with the service, such as
        /// serverless network endpoint groups, should read this rather than
        /// assuming the project's default region.
        public var location: Output<String> {
            service.output.keyPath("location")
        }

        /// Cloud Run injects `PORT` into the container from `containerPort`, and
        /// rejects deployments that set it explicitly, so it is not added to the
        /// environment here.
        public init(
            _ name: String,
            image: any Input<String>,
            serviceAccount: ServiceAccount? = nil,
            location: Region? = nil,
            port: Int = 8080,
            protocol containerProtocol: ContainerProtocol = .http1,
            cpu: Int = 1,
            memory: String = "512Mi",
            cpuAllocation: CPUAllocation = .requestOnly,
            requestConcurrency: Int = 80,
            timeout: Duration = .seconds(300),
            scaling: Scaling = .init(maximumInstances: 10),
            ingress: Ingress = .all,
            vpc: VPC? = nil,
            vpcEgress: VPCEgress = .privateRangesOnly,
            environment: [String: any Input<String>] = [:],
            secretEnvironment: [SecretEnvironmentVariable] = [],
            arguments: [String] = [],
            applicationDependencies: [String] = [],
            applicationVolumeMounts: [VolumeMount] = [],
            sidecars: [Sidecar] = [],
            volumes: [Volume] = [],
            publicAccess: Bool = false,
            deletionProtection: Bool = false,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            precondition((1...65_535).contains(port), "port must be a valid TCP port")
            precondition((1...1_000).contains(requestConcurrency), "requestConcurrency must be between 1 and 1000")
            precondition([1, 2, 4, 6, 8].contains(cpu), "cpu must be one of 1, 2, 4, 6, or 8")
            precondition(
                (1...3_600).contains(timeout.components.seconds),
                "timeout must be between 1 and 3600 seconds"
            )
            precondition(scaling.minimumInstances >= 0, "minimumInstances must not be negative")
            precondition(scaling.maximumInstances >= 1, "maximumInstances must be at least one")
            precondition(
                scaling.minimumInstances <= scaling.maximumInstances,
                "minimumInstances must not exceed maximumInstances"
            )

            self.serviceAccount = serviceAccount
            self.environment = Environment(environment, shape: .nameValueList, context: context)

            let applicationContainer = Self.containerProperties(
                name: "app",
                image: image,
                port: port,
                containerProtocol: containerProtocol,
                cpu: cpu,
                memory: memory,
                cpuAllocation: cpuAllocation,
                environment: AnyEncodable(
                    CloudRunEnvironment(
                        environment: self.environment,
                        secrets: secretEnvironment
                    )
                ),
                arguments: arguments,
                dependencies: applicationDependencies,
                volumeMounts: applicationVolumeMounts,
                startupProbe: nil,
                livenessProbe: nil
            )

            let serviceName = tokenize(context.gcpStage, name, maxLength: 49)
            service = Resource(
                name: name,
                type: "gcp:cloudrunv2:Service",
                properties: [
                    "project": context.gcpProjectID,
                    "name": serviceName,
                    "location": (location ?? context.gcpRegion).rawValue,
                    "ingress": ingress.rawValue,
                    "deletionProtection": deletionProtection,
                    "scaling": [
                        "minInstanceCount": scaling.minimumInstances,
                        "maxInstanceCount": scaling.maximumInstances,
                    ],
                    "template": [
                        "serviceAccount": AnyEncodable(serviceAccount?.email),
                        "maxInstanceRequestConcurrency": requestConcurrency,
                        "timeout": "\(timeout.components.seconds)s",
                        "containers": [applicationContainer] + sidecars.map(\.properties),
                        "volumes": volumes.map(\.properties),
                        "vpcAccess": Self.vpcAccessProperties(vpc, egress: vpcEgress),
                    ],
                    "traffics": [
                        [
                            "percent": 100,
                            "type": "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST",
                        ]
                    ],
                ],
                options: options,
                context: context
            )

            if publicAccess {
                _ = allowInvocation(member: "allUsers", bindingName: "public")
            }
        }
    }
}

extension GCP.CloudRunService {
    public enum ContainerProtocol: String, Sendable {
        case http1
        case http2 = "h2c"
    }

    public enum CPUAllocation: Sendable {
        case requestOnly
        case always

        var isIdleBetweenRequests: Bool {
            switch self {
            case .requestOnly:
                true
            case .always:
                false
            }
        }
    }

    public enum Ingress: String, Sendable {
        case all = "INGRESS_TRAFFIC_ALL"
        case internalOnly = "INGRESS_TRAFFIC_INTERNAL_ONLY"
        case internalLoadBalancer = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
    }

    public enum VPCEgress: String, Sendable {
        case allTraffic = "ALL_TRAFFIC"
        case privateRangesOnly = "PRIVATE_RANGES_ONLY"
    }

    public struct Scaling: Sendable {
        public let minimumInstances: Int
        public let maximumInstances: Int

        public init(minimumInstances: Int = 0, maximumInstances: Int) {
            self.minimumInstances = minimumInstances
            self.maximumInstances = maximumInstances
        }
    }
}

extension GCP.CloudRunService {
    public struct SecretEnvironmentVariable: Sendable {
        public let name: String
        public let secret: any Input<String>
        public let version: any Input<String>

        public init(
            _ name: String,
            secret: any Input<String>,
            version: any Input<String> = "latest"
        ) {
            self.name = name
            self.secret = secret
            self.version = version
        }

        var properties: AnyEncodable {
            [
                "name": Self.environmentKey(name),
                "valueSource": [
                    "secretKeyRef": [
                        "secret": secret,
                        "version": version,
                    ]
                ],
            ]
        }

        static func environmentKey(_ key: String) -> String {
            tokenize(key, separator: "_").uppercased()
        }
    }
}

extension GCP.CloudRunService {
    public struct VolumeMount: Sendable {
        public let name: String
        public let path: String

        public init(_ name: String, path: String) {
            self.name = name
            self.path = path
        }

        var properties: AnyEncodable {
            [
                "name": name,
                "mountPath": path,
            ]
        }
    }

    public struct SecretVolumeItem: Sendable {
        public let version: any Input<String>
        public let path: String

        public init(version: any Input<String> = "latest", path: String) {
            self.version = version
            self.path = path
        }

        var properties: AnyEncodable {
            [
                "version": version,
                "path": path,
            ]
        }
    }

    public enum Volume: Sendable {
        case cloudSQL(name: String, instances: [any Input<String>])
        case secret(name: String, secret: any Input<String>, items: [SecretVolumeItem])

        var properties: AnyEncodable {
            switch self {
            case .cloudSQL(let name, let instances):
                [
                    "name": name,
                    "cloudSqlInstance": [
                        "instances": instances.map(AnyEncodable.init)
                    ],
                ]
            case .secret(let name, let secret, let items):
                [
                    "name": name,
                    "secret": [
                        "secret": secret,
                        "items": items.map(\.properties),
                    ],
                ]
            }
        }
    }
}

extension GCP.CloudRunService {
    public enum Probe: Sendable {
        case grpc(port: Int, service: String? = nil)
        case http(path: String, port: Int)
        case tcp(port: Int)

        fileprivate var properties: AnyEncodable {
            switch self {
            case .grpc(let port, let service):
                ["grpc": ["port": port, "service": AnyEncodable(service)]]
            case .http(let path, let port):
                ["httpGet": ["path": path, "port": port]]
            case .tcp(let port):
                ["tcpSocket": ["port": port]]
            }
        }
    }

    public struct Sidecar: Sendable {
        public let name: String
        public let image: any Input<String>
        public let cpu: Int
        public let memory: String
        public let cpuAllocation: CPUAllocation
        public let environment: [String: any Input<String>]
        public let secretEnvironment: [SecretEnvironmentVariable]
        public let arguments: [String]
        public let dependencies: [String]
        public let volumeMounts: [VolumeMount]
        public let startupProbe: Probe?
        public let livenessProbe: Probe?

        public init(
            _ name: String,
            image: any Input<String>,
            cpu: Int = 1,
            memory: String = "512Mi",
            cpuAllocation: CPUAllocation = .requestOnly,
            environment: [String: any Input<String>] = [:],
            secretEnvironment: [SecretEnvironmentVariable] = [],
            arguments: [String] = [],
            dependencies: [String] = [],
            volumeMounts: [VolumeMount] = [],
            startupProbe: Probe? = nil,
            livenessProbe: Probe? = nil
        ) {
            precondition([1, 2, 4, 6, 8].contains(cpu), "cpu must be one of 1, 2, 4, 6, or 8")

            self.name = name
            self.image = image
            self.cpu = cpu
            self.memory = memory
            self.cpuAllocation = cpuAllocation
            self.environment = environment
            self.secretEnvironment = secretEnvironment
            self.arguments = arguments
            self.dependencies = dependencies
            self.volumeMounts = volumeMounts
            self.startupProbe = startupProbe
            self.livenessProbe = livenessProbe
        }

        fileprivate var properties: AnyEncodable {
            GCP.CloudRunService.containerProperties(
                name: name,
                image: image,
                port: nil,
                containerProtocol: .http1,
                cpu: cpu,
                memory: memory,
                cpuAllocation: cpuAllocation,
                environment: GCP.CloudRunService.environmentProperties(
                    environment,
                    secrets: secretEnvironment
                ),
                arguments: arguments,
                dependencies: dependencies,
                volumeMounts: volumeMounts,
                startupProbe: startupProbe,
                livenessProbe: livenessProbe
            )
        }
    }
}

extension GCP.CloudRunService {
    @discardableResult
    public func allowInvocation(from serviceAccount: GCP.ServiceAccount) -> Self {
        allowInvocation(
            member: serviceAccount.member,
            bindingName: serviceAccount.resource.chosenName
        )
    }

    @discardableResult
    public func makePublic() -> Self {
        allowInvocation(member: "allUsers", bindingName: "public")
    }

    @discardableResult
    private func allowInvocation(
        member: any Input<String>,
        bindingName: String
    ) -> Self {
        _ = Resource(
            name: "\(service.chosenName)-invoker-\(bindingName)",
            type: "gcp:cloudrunv2:ServiceIamMember",
            properties: [
                "project": service.context.gcpProjectID,
                "location": service.output.keyPath("location"),
                "name": service.name,
                "role": GCP.IAMRole.runInvoker.rawValue,
                "member": member,
            ],
            options: service.options,
            context: service.context
        )
        return self
    }
}

extension GCP.CloudRunService {
    private static func containerProperties(
        name: String,
        image: any Input<String>,
        port: Int?,
        containerProtocol: ContainerProtocol,
        cpu: Int,
        memory: String,
        cpuAllocation: CPUAllocation,
        environment: AnyEncodable,
        arguments: [String],
        dependencies: [String],
        volumeMounts: [VolumeMount],
        startupProbe: Probe?,
        livenessProbe: Probe?
    ) -> AnyEncodable {
        return [
            "name": name,
            "image": image,
            "args": arguments,
            "dependsOns": dependencies,
            "ports": port.map {
                [
                    "name": containerProtocol.rawValue,
                    "containerPort": $0,
                ]
            },
            "resources": [
                "cpuIdle": cpuAllocation.isIdleBetweenRequests,
                "limits": [
                    "cpu": "\(cpu)",
                    "memory": memory,
                ],
            ],
            "envs": environment,
            "volumeMounts": volumeMounts.map(\.properties),
            "startupProbe": startupProbe?.properties,
            "livenessProbe": livenessProbe?.properties,
        ]
    }

    /// The `vpcAccess` block, shared by every Cloud Run workload shape.
    static func vpcAccessProperties(_ vpc: GCP.VPC?, egress: VPCEgress) -> AnyEncodable {
        AnyEncodable(
            vpc.map {
                [
                    "egress": egress.rawValue,
                    "networkInterfaces": [
                        [
                            "network": $0.network.id,
                            "subnetwork": $0.subnetwork.id,
                        ]
                    ],
                ]
            }
        )
    }

    static func environmentProperties(
        _ environment: [String: any Input<String>],
        secrets: [SecretEnvironmentVariable]
    ) -> AnyEncodable {
        // Literal keys and secret names normalize through the same tokenizer, so
        // distinct inputs can land on one name. Cloud Run rejects duplicate env
        // names outright, and a secret is the more specific declaration, so it wins.
        var claimedNames = Set(secrets.map { SecretEnvironmentVariable.environmentKey($0.name) })
        let literalEnvironment =
            environment
            .map { (name: SecretEnvironmentVariable.environmentKey($0.key), value: $0.value) }
            .sorted { $0.name < $1.name }
            .filter { claimedNames.insert($0.name).inserted }
            .map { AnyEncodable(["name": $0.name, "value": $0.value]) }
        return AnyEncodable(literalEnvironment + secrets.map(\.properties))
    }
}

struct CloudRunEnvironment: Encodable, Sendable {
    let environment: Environment
    let secrets: [GCP.CloudRunService.SecretEnvironmentVariable]

    func encode(to encoder: Encoder) throws {
        try GCP.CloudRunService.environmentProperties(
            environment.values,
            secrets: secrets
        ).encode(to: encoder)
    }
}

extension GCP.CloudRunService: EnvironmentProvider, GCPRoleProvider {
    public var gcpServiceAccount: GCP.ServiceAccount {
        guard let serviceAccount else {
            preconditionFailure("Linking a Cloud Run service requires an explicit service account")
        }
        return serviceAccount
    }

    public var gcpContext: Context {
        service.context
    }
}
