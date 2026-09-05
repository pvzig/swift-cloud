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
    public struct Provider: ResourcePropertyProvider {
        public let resource: Resource
        public let projectID: String
        public let region: Region

        public init(
            _ name: String,
            projectID: String,
            region: Region = .usCentral1,
            zone: String? = nil,
            context: Context = .current
        ) {
            self.projectID = projectID
            self.region = region
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

        public func resourceProperties(
            _ properties: AnyEncodable?,
            in _: Context
        ) -> AnyEncodable? {
            if var properties = properties?.value as? [String: Any?] {
                rewriteProject(in: &properties)
                return AnyEncodable(properties)
            }
            if var properties = properties?.value as? [String: AnyEncodable] {
                var unwrapped = properties.mapValues { $0.value as Any? }
                rewriteProject(in: &unwrapped)
                properties = unwrapped.mapValues(AnyEncodable.init)
                return AnyEncodable(properties)
            }
            return properties
        }

        private func rewriteProject(in properties: inout [String: Any?]) {
            if properties["project"] != nil {
                properties["project"] = projectID
            }
        }
    }
}
