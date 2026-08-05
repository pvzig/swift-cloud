import CloudCore

extension Provider {
    public static func gcp(
        projectID: String,
        region: GCP.Region = .usCentral1,
        zone: String? = nil
    ) -> Self {
        .init(
            plugin: .gcp,
            configuration: [
                "project": projectID,
                "region": region.rawValue,
                "zone": zone,
            ],
            dependencies: [.dockerBuild]
        )
    }
}

extension GCP {
    public struct Provider: ResourceProvider {
        public let resource: Resource

        public init(
            _ name: String,
            projectID: String,
            region: Region = .usCentral1,
            zone: String? = nil,
            context: Context = .current
        ) {
            resource = Resource(
                name: name,
                type: "pulumi:providers:gcp",
                properties: [
                    "project": projectID,
                    "region": region.rawValue,
                    "zone": zone,
                ],
                options: nil,
                context: context
            )
        }
    }
}
