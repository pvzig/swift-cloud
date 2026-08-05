extension GCP {
    public struct IAMRole: RawRepresentable, Sendable, ExpressibleByStringLiteral {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            self.init(rawValue: value)
        }
    }
}

extension GCP.IAMRole {
    public static let cloudSQLClient: Self = "roles/cloudsql.client"
    public static let loggingWriter: Self = "roles/logging.logWriter"
    public static let monitoringMetricWriter: Self = "roles/monitoring.metricWriter"
    public static let pubSubPublisher: Self = "roles/pubsub.publisher"
    public static let pubSubSubscriber: Self = "roles/pubsub.subscriber"
    public static let runInvoker: Self = "roles/run.invoker"
    public static let secretAccessor: Self = "roles/secretmanager.secretAccessor"
    public static let serviceAccountTokenCreator: Self = "roles/iam.serviceAccountTokenCreator"
    public static let serviceController: Self = "roles/servicemanagement.serviceController"
    public static let traceAgent: Self = "roles/cloudtrace.agent"
}
