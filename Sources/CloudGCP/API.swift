extension GCP {
    public struct API: RawRepresentable, Sendable, ExpressibleByStringLiteral {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            self.init(rawValue: value)
        }
    }
}

extension GCP.API {
    public static let apiGateway: Self = "apigateway.googleapis.com"
    public static let artifactRegistry: Self = "artifactregistry.googleapis.com"
    public static let cloudDNS: Self = "dns.googleapis.com"
    public static let cloudRun: Self = "run.googleapis.com"
    public static let cloudScheduler: Self = "cloudscheduler.googleapis.com"
    public static let cloudSQL: Self = "sqladmin.googleapis.com"
    public static let cloudTasks: Self = "cloudtasks.googleapis.com"
    public static let compute: Self = "compute.googleapis.com"
    public static let endpoints: Self = "endpoints.googleapis.com"
    public static let eventarc: Self = "eventarc.googleapis.com"
    public static let firestore: Self = "firestore.googleapis.com"
    public static let pubSub: Self = "pubsub.googleapis.com"
    public static let redis: Self = "redis.googleapis.com"
    public static let secretManager: Self = "secretmanager.googleapis.com"
    public static let serviceControl: Self = "servicecontrol.googleapis.com"
    public static let serviceManagement: Self = "servicemanagement.googleapis.com"
    public static let serviceNetworking: Self = "servicenetworking.googleapis.com"
    public static let spanner: Self = "spanner.googleapis.com"
    public static let storage: Self = "storage.googleapis.com"
    public static let workflows: Self = "workflows.googleapis.com"
}
