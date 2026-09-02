import CloudCore

extension GCP {
    /// A Cloud Tasks queue for asynchronous, push-oriented work.
    public struct TaskQueue: GCPComponent {
        public let queue: Resource

        public var name: Output<String> {
            queue.name
        }

        public var id: Output<String> {
            queue.id
        }

        public init(
            _ name: String,
            location: Region? = nil,
            state: State = .running,
            rateLimits: RateLimits = .init(),
            retry: Retry = .init(),
            target: Target? = nil,
            loggingSampleRatio: Double = 1,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            precondition(
                (0...1).contains(loggingSampleRatio),
                "loggingSampleRatio must be between 0 and 1"
            )
            rateLimits.validate()
            retry.validate()
            target?.grantInvocation()

            queue = Resource(
                name: name,
                type: "gcp:cloudtasks:Queue",
                properties: [
                    "project": context.gcpProjectID,
                    "location": (location ?? context.gcpRegion).rawValue,
                    "name": tokenize(context.gcpStage, name, maxLength: 100),
                    "desiredState": state.rawValue,
                    "rateLimits": rateLimits.properties,
                    "retryConfig": retry.properties,
                    "httpTarget": target?.properties,
                    "stackdriverLoggingConfig": [
                        "samplingRatio": loggingSampleRatio
                    ],
                ],
                options: options,
                context: context
            )
        }
    }
}

extension GCP.TaskQueue {
    public enum State: String, Sendable {
        case paused = "PAUSED"
        case running = "RUNNING"
    }

    public struct RateLimits: Sendable {
        public let maximumConcurrentDispatches: Int?
        public let maximumDispatchesPerSecond: Double?

        public init(
            maximumConcurrentDispatches: Int? = nil,
            maximumDispatchesPerSecond: Double? = nil
        ) {
            self.maximumConcurrentDispatches = maximumConcurrentDispatches
            self.maximumDispatchesPerSecond = maximumDispatchesPerSecond
        }

        fileprivate var properties: AnyEncodable {
            [
                "maxConcurrentDispatches": maximumConcurrentDispatches,
                "maxDispatchesPerSecond": maximumDispatchesPerSecond,
            ]
        }

        fileprivate func validate() {
            if let maximumConcurrentDispatches {
                precondition(
                    maximumConcurrentDispatches > 0,
                    "maximumConcurrentDispatches must be greater than zero"
                )
            }
            if let maximumDispatchesPerSecond {
                precondition(
                    maximumDispatchesPerSecond > 0,
                    "maximumDispatchesPerSecond must be greater than zero"
                )
            }
        }
    }

    public struct Retry: Sendable {
        public let maximumAttempts: Int
        public let maximumRetryDuration: Duration
        public let minimumBackoff: Duration
        public let maximumBackoff: Duration
        public let maximumDoublings: Int

        public init(
            maximumAttempts: Int = 5,
            maximumRetryDuration: Duration = .seconds(3_600),
            minimumBackoff: Duration = .seconds(1),
            maximumBackoff: Duration = .seconds(3_600),
            maximumDoublings: Int = 5
        ) {
            self.maximumAttempts = maximumAttempts
            self.maximumRetryDuration = maximumRetryDuration
            self.minimumBackoff = minimumBackoff
            self.maximumBackoff = maximumBackoff
            self.maximumDoublings = maximumDoublings
        }

        fileprivate var properties: AnyEncodable {
            [
                "maxAttempts": maximumAttempts,
                "maxRetryDuration": maximumRetryDuration.protobufString,
                "minBackoff": minimumBackoff.protobufString,
                "maxBackoff": maximumBackoff.protobufString,
                "maxDoublings": maximumDoublings,
            ]
        }

        fileprivate func validate() {
            precondition(
                maximumAttempts == -1 || maximumAttempts > 0, "maximumAttempts must be -1 or greater than zero")
            precondition(maximumRetryDuration >= .zero, "maximumRetryDuration must not be negative")
            precondition(minimumBackoff >= .zero, "minimumBackoff must not be negative")
            precondition(maximumBackoff >= minimumBackoff, "maximumBackoff must not precede minimumBackoff")
            precondition(maximumDoublings >= 0, "maximumDoublings must not be negative")
        }
    }

    public enum Target: Sendable {
        case cloudRun(GCP.CloudRunService, serviceAccount: GCP.ServiceAccount)
        case oidc(serviceAccount: GCP.ServiceAccount, audience: any Input<String>)

        fileprivate var properties: AnyEncodable {
            switch self {
            case .cloudRun(let service, let serviceAccount):
                [
                    "oidcToken": [
                        "serviceAccountEmail": serviceAccount.email,
                        "audience": service.url,
                    ]
                ]
            case .oidc(let serviceAccount, let audience):
                [
                    "oidcToken": [
                        "serviceAccountEmail": serviceAccount.email,
                        "audience": audience,
                    ]
                ]
            }
        }

        fileprivate func grantInvocation() {
            switch self {
            case .cloudRun(let service, let serviceAccount):
                service.allowInvocation(from: serviceAccount)
            case .oidc:
                break
            }
        }
    }
}

extension GCP.TaskQueue {
    @discardableResult
    public func allowEnqueuing(from serviceAccount: GCP.ServiceAccount) -> Self {
        _ = enqueuerGrant(for: serviceAccount)
        return self
    }

    private func enqueuerGrant(for serviceAccount: GCP.ServiceAccount) -> Resource {
        Resource(
            name: "\(queue.chosenName)-enqueuer-\(serviceAccount.resource.chosenName)",
            type: "gcp:cloudtasks:QueueIamMember",
            properties: [
                "project": queue.context.gcpProjectID,
                "location": queue.output.keyPath("location"),
                "name": name,
                "role": GCP.IAMRole.cloudTasksEnqueuer.rawValue,
                "member": serviceAccount.member,
            ],
            options: queue.options,
            context: queue.context
        )
    }
}

extension GCP.TaskQueue: GCPLinkable {
    public func grantAccess(to serviceAccount: GCP.ServiceAccount) {
        _ = accessGrants(to: serviceAccount)
    }

    public var actions: [String] {
        [GCP.IAMRole.cloudTasksEnqueuer.rawValue]
    }

    public var resources: [Output<String>] {
        [id]
    }

    public var properties: LinkProperties? {
        .init(
            type: "queue",
            name: queue.chosenName,
            properties: [
                "name": name,
                "id": id,
                "location": queue.output.keyPath("location"),
            ]
        )
    }

    public func accessGrants(to serviceAccount: GCP.ServiceAccount) -> [any ResourceProvider] {
        [enqueuerGrant(for: serviceAccount)]
    }
}
