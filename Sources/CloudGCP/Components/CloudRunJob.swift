import CloudCore

extension GCP {
    /// A containerized Cloud Run workload that runs to completion.
    public struct CloudRunJob: GCPComponent {
        public let job: Resource
        public let serviceAccount: ServiceAccount?
        public let environment: Environment

        public var name: Output<String> {
            job.name
        }

        public var runURI: Output<String> {
            let location = job.output.keyPath("location") as Output<String>
            return
                "https://run.googleapis.com/v2/projects/\(job.context.gcpProjectID)/locations/\(location)/jobs/\(name):run"
        }

        public init(
            _ name: String,
            image: any Input<String>,
            serviceAccount: ServiceAccount? = nil,
            location: Region? = nil,
            taskCount: Int = 1,
            parallelism: Int = 1,
            maximumRetries: Int = 3,
            timeout: Duration = .seconds(600),
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
            precondition((1...10_000).contains(taskCount), "taskCount must be between 1 and 10000")
            precondition((1...taskCount).contains(parallelism), "parallelism must be between 1 and taskCount")
            precondition((0...10).contains(maximumRetries), "maximumRetries must be between 0 and 10")
            precondition(
                (.seconds(1)...Duration.seconds(604_800)).contains(timeout),
                "timeout must be between 1 second and 7 days"
            )
            precondition([1, 2, 4, 6, 8].contains(cpu), "cpu must be one of 1, 2, 4, 6, or 8")
            CloudRunService.validateSecretEnvironment(secretEnvironment)

            self.serviceAccount = serviceAccount
            self.environment = Environment(environment, shape: .nameValueList, context: context)

            let jobName = tokenize(context.gcpStage, name, maxLength: 49)
            job = Resource(
                name: name,
                type: "gcp:cloudrunv2:Job",
                properties: [
                    "project": context.gcpProjectID,
                    "name": jobName,
                    "location": (location ?? context.gcpRegion).rawValue,
                    "deletionProtection": deletionProtection,
                    "template": [
                        "taskCount": taskCount,
                        "parallelism": parallelism,
                        "template": [
                            "serviceAccount": AnyEncodable(serviceAccount?.email),
                            "maxRetries": maximumRetries,
                            "timeout": timeout.protobufString,
                            "containers": [
                                [
                                    "name": "job",
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
                ],
                options: options,
                context: context
            )
        }
    }
}

extension GCP.CloudRunJob {
    /// Grants a service account permission to execute this job.
    @discardableResult
    public func allowExecution(from serviceAccount: GCP.ServiceAccount) -> Self {
        _ = Resource(
            name: "\(job.chosenName)-invoker-\(serviceAccount.resource.chosenName)",
            type: "gcp:cloudrunv2:JobIamMember",
            properties: [
                "project": job.context.gcpProjectID,
                "location": job.output.keyPath("location"),
                "name": name,
                "role": GCP.IAMRole.runInvoker.rawValue,
                "member": serviceAccount.member,
            ],
            options: job.options,
            context: job.context
        )
        return self
    }
}

extension GCP.CloudRunJob: EnvironmentProvider, GCPRoleProvider {
    public var gcpResource: Resource? {
        job
    }

    public var gcpServiceAccount: GCP.ServiceAccount {
        guard let serviceAccount else {
            preconditionFailure("Linking a Cloud Run job requires an explicit service account")
        }
        return serviceAccount
    }

    public var gcpContext: Context {
        job.context
    }
}
