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
            _ = name
            resource = GCP.sharedResource(
                name: "\(tokenize(api.rawValue))-service-identity",
                type: "gcp:projects:ServiceIdentity",
                properties: [
                    "project": context.gcpProjectID,
                    "service": api.rawValue,
                ],
                options: options,
                context: context
            )
        }

        /// Returns the project's service agent for `api`, materializing it once.
        ///
        /// A service agent is a project-scoped resource, so components that need one
        /// share a single owner instead of each declaring a competing resource for
        /// the same underlying identity.
        public static func shared(
            _ api: API,
            options: Resource.Options? = nil,
            context: Context = .current
        ) -> Self {
            let name = "\(tokenize(api.rawValue))-service-identity"
            let resource = GCP.sharedResource(
                name: name,
                type: "gcp:projects:ServiceIdentity",
                properties: [
                    "project": context.gcpProjectID,
                    "service": api.rawValue,
                ],
                options: options,
                context: context
            )
            return .init(resource: resource)
        }

        private init(resource: Resource) {
            self.resource = resource
        }
    }
}
