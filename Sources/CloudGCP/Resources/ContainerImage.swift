import CloudCore

extension GCP {
    /// Builds a Swift executable into an amd64 image and pushes it to Artifact Registry.
    ///
    /// Artifact Registry authentication is intentionally delegated to Docker's
    /// credential store. Run `gcloud auth configure-docker` for the repository's
    /// regional hostname before deploying.
    public struct ContainerImage: GCPResourceProvider {
        public let resource: Resource

        public var digest: Output<String> {
            resource.output.keyPath("digest")
        }

        /// An immutable registry reference containing the pushed image digest.
        public var reference: Output<String> {
            resource.output.keyPath("ref")
        }

        public init(
            _ name: String,
            targetName: String,
            repository: ArtifactRegistry,
            instancePort: Int = 8080,
            arguments: [String] = [],
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            precondition((1...65_535).contains(instancePort), "instancePort must be a valid TCP port")

            let architecture = Architecture.x86
            let dockerFilePath = Docker.Dockerfile.filePath(name)
            let imageName = tokenize(context.stage, name)
            let imageTag = "\(repository.registryURI)/\(imageName):\(context.stage)"

            resource = Resource(
                name: name,
                type: "docker-build:Image",
                properties: [
                    "push": true,
                    "dockerfile": ["location": dockerFilePath],
                    "context": ["location": Context.projectDirectory],
                    "platforms": ["linux/amd64"],
                    "tags": [imageTag],
                ],
                options: options,
                context: context,
                dependsOn: [repository]
            )

            context.store.build { context in
                let dockerFile = Docker.Dockerfile.ubuntu(
                    targetName: targetName,
                    architecture: architecture,
                    port: instancePort,
                    arguments: arguments
                )
                try Docker.Dockerfile.write(dockerFile, to: dockerFilePath)
                try await context.builder.buildUbuntu(
                    targetName: targetName,
                    architecture: architecture
                )
            }
        }
    }
}
