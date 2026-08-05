import CloudCore

extension GCP {
    /// Materializes the Google-managed service agent for an activated API.
    public struct ServiceIdentity: GCPResourceProvider {
        public let resource: Resource

        public var email: Output<String> {
            resource.output.keyPath("email")
        }

        public var member: Output<String> {
            resource.output.keyPath("member")
        }

        public init(
            _ name: String,
            service api: API,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            resource = Resource(
                name: name,
                type: "gcp:projects:ServiceIdentity",
                properties: [
                    "project": context.gcpProjectID,
                    "service": api.rawValue,
                ],
                options: options,
                context: context
            )
        }
    }
}
