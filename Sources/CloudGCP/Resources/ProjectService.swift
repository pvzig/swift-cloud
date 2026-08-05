import CloudCore

extension GCP {
    /// Owns activation of one Google API for the configured project.
    ///
    /// Declare each API once per project. Google API activation is a shared,
    /// project-scoped resource, so individual components deliberately do not
    /// create their own competing `ProjectService` resources.
    public struct ProjectService: GCPResourceProvider {
        public let resource: Resource

        public init(
            _ api: API,
            disableOnDestroy: Bool = false,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            resource = Resource(
                name: "\(tokenize(api.rawValue))-api",
                type: "gcp:projects:Service",
                properties: [
                    "project": context.gcpProjectID,
                    "service": api.rawValue,
                    "disableOnDestroy": disableOnDestroy,
                ],
                options: options,
                context: context
            )
        }
    }
}
