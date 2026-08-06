import CloudCore

extension GCP {
    public struct ArtifactRegistry: GCPResourceProvider {
        public let resource: Resource

        public var registryURI: Output<String> {
            resource.output.keyPath("registryUri")
        }

        public var repositoryID: Output<String> {
            resource.output.keyPath("repositoryId")
        }

        public init(
            _ name: String,
            location: Region? = nil,
            description: String? = nil,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            resource = Resource(
                name: name,
                type: "gcp:artifactregistry:Repository",
                properties: [
                    "project": context.gcpProjectID,
                    "location": (location ?? context.gcpRegion).rawValue,
                    "repositoryId": tokenize(context.gcpStage, name),
                    "description": description,
                    "format": "DOCKER",
                ],
                options: options,
                context: context
            )
        }
    }
}
