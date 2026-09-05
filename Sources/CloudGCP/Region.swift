extension GCP {
    public struct Region: Equatable, RawRepresentable, Sendable, ExpressibleByStringLiteral {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            self.init(rawValue: value)
        }
    }
}

extension GCP.Region {
    public static let asiaNortheast1: Self = "asia-northeast1"
    public static let asiaSoutheast1: Self = "asia-southeast1"
    public static let europeWest1: Self = "europe-west1"
    public static let europeWest4: Self = "europe-west4"
    public static let usCentral1: Self = "us-central1"
    public static let usEast1: Self = "us-east1"
    public static let usEast4: Self = "us-east4"
    public static let usWest1: Self = "us-west1"
}
