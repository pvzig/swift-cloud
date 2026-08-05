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
    public static let artifactRegistry: Self = "artifactregistry.googleapis.com"
    public static let cloudRun: Self = "run.googleapis.com"
    public static let cloudSQL: Self = "sqladmin.googleapis.com"
    public static let endpoints: Self = "endpoints.googleapis.com"
    public static let pubSub: Self = "pubsub.googleapis.com"
    public static let secretManager: Self = "secretmanager.googleapis.com"
    public static let serviceControl: Self = "servicecontrol.googleapis.com"
    public static let serviceManagement: Self = "servicemanagement.googleapis.com"
}
