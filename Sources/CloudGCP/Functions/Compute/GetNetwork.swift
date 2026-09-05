import CloudCore

extension GCP {
    public enum Compute {}
}

extension GCP.Compute {
    public struct GetNetwork: Sendable {
        public let id: String
        public let name: String
        public let networkId: Int
        public let project: String
        public let selfLink: String
        public let subnetworksSelfLinks: [String]
    }

    public static func getNetwork(
        name: any Input<String>,
        project: String? = nil,
        context: Context = .current
    ) -> Output<GetNetwork> {
        let project = project ?? context.gcpProjectID
        return Variable<GetNetwork>.invoke(
            name: "\(name)-\(digest(name, project))-network",
            function: "gcp:compute:getNetwork",
            arguments: [
                "name": name,
                "project": project,
            ],
            context: context
        ).output
    }
}
