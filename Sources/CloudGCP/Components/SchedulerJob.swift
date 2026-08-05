import CloudCore

extension GCP {
    public struct SchedulerJob: GCPComponent {
        public let job: Resource

        public var name: Output<String> {
            job.name
        }

        public init(
            _ name: String,
            schedule: String,
            target: Target,
            location: Region? = nil,
            timeZone: String = "Etc/UTC",
            paused: Bool = false,
            attemptDeadline: Duration = .seconds(180),
            retry: Retry = .init(),
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            precondition(
                (15...1_800).contains(attemptDeadline.components.seconds),
                "attemptDeadline must be between 15 and 1800 seconds"
            )
            target.validate()

            job = Resource(
                name: name,
                type: "gcp:cloudscheduler:Job",
                properties: [
                    "project": context.gcpProjectID,
                    "region": (location ?? context.gcpRegion).rawValue,
                    "name": tokenize(context.stage, name),
                    "schedule": schedule,
                    "timeZone": timeZone,
                    "paused": paused,
                    "attemptDeadline": "\(attemptDeadline.components.seconds)s",
                    "httpTarget": target.httpProperties,
                    "pubsubTarget": target.pubSubProperties,
                    "retryConfig": retry.properties,
                ],
                options: options,
                context: context
            )
        }
    }
}

extension GCP.SchedulerJob {
    public enum HTTPMethod: String, Sendable {
        case delete = "DELETE"
        case get = "GET"
        case patch = "PATCH"
        case post = "POST"
        case put = "PUT"
    }

    public enum Target: Sendable {
        case http(
            uri: any Input<String>,
            method: HTTPMethod,
            serviceAccount: GCP.ServiceAccount?,
            audience: (any Input<String>)?,
            headers: [String: String],
            bodyBase64: String?
        )
        case pubSub(topic: GCP.Topic, dataBase64: String?, attributes: [String: String])

        public static func cloudRun(
            _ service: GCP.CloudRunService,
            path: String = "",
            method: HTTPMethod = .post,
            serviceAccount: GCP.ServiceAccount,
            headers: [String: String] = [:],
            bodyBase64: String? = nil
        ) -> Self {
            service.allowInvocation(from: serviceAccount)
            return .http(
                uri: "\(service.url)\(path)",
                method: method,
                serviceAccount: serviceAccount,
                audience: service.url,
                headers: headers,
                bodyBase64: bodyBase64
            )
        }

        fileprivate var httpProperties: AnyEncodable? {
            switch self {
            case .http(let uri, let method, let serviceAccount, let audience, let headers, let bodyBase64):
                [
                    "uri": uri,
                    "httpMethod": method.rawValue,
                    "headers": headers,
                    "body": bodyBase64,
                    "oidcToken": serviceAccount.map {
                        [
                            "serviceAccountEmail": $0.email,
                            "audience": AnyEncodable(audience),
                        ]
                    },
                ]
            case .pubSub:
                nil
            }
        }

        fileprivate var pubSubProperties: AnyEncodable? {
            switch self {
            case .http:
                nil
            case .pubSub(let topic, let dataBase64, let attributes):
                [
                    "topicName": topic.id,
                    "data": dataBase64,
                    "attributes": attributes,
                ]
            }
        }

        fileprivate func validate() {
            switch self {
            case .http(_, let method, let serviceAccount, let audience, _, let bodyBase64):
                if bodyBase64 != nil {
                    precondition(
                        [.patch, .post, .put].contains(method),
                        "HTTP bodies require PATCH, POST, or PUT"
                    )
                }
                precondition(
                    serviceAccount != nil || audience == nil,
                    "an OIDC audience requires a service account"
                )
            case .pubSub(_, let dataBase64, let attributes):
                precondition(
                    dataBase64?.isEmpty == false || attributes.isEmpty == false,
                    "a Pub/Sub target requires data or at least one attribute"
                )
            }
        }
    }

    public struct Retry: Sendable {
        public let retryCount: Int
        public let minimumBackoff: Duration
        public let maximumBackoff: Duration
        public let maximumDoublings: Int

        public init(
            retryCount: Int = 3,
            minimumBackoff: Duration = .seconds(5),
            maximumBackoff: Duration = .seconds(3600),
            maximumDoublings: Int = 5
        ) {
            precondition((0...5).contains(retryCount), "retryCount must be between 0 and 5")
            precondition(minimumBackoff >= .zero, "minimumBackoff must not be negative")
            precondition(maximumBackoff >= minimumBackoff, "maximumBackoff must not precede minimumBackoff")
            precondition(maximumDoublings >= 0, "maximumDoublings must not be negative")
            self.retryCount = retryCount
            self.minimumBackoff = minimumBackoff
            self.maximumBackoff = maximumBackoff
            self.maximumDoublings = maximumDoublings
        }

        fileprivate var properties: AnyEncodable {
            [
                "retryCount": retryCount,
                "minBackoffDuration": "\(minimumBackoff.components.seconds)s",
                "maxBackoffDuration": "\(maximumBackoff.components.seconds)s",
                "maxDoublings": maximumDoublings,
            ]
        }
    }
}
