import CloudCore

extension GCP.Compute {
    public struct GetSubnetwork: Sendable {
        public let gatewayAddress: String
        public let id: String
        public let ipCidrRange: String
        public let name: String
        public let network: String
        public let project: String
        public let region: String
        public let selfLink: String
        public let subnetworkId: Int
    }

    public static func getSubnetwork(
        name: any Input<String>,
        location: GCP.Region? = nil,
        project: String? = nil,
        context: Context = .current
    ) -> Output<GetSubnetwork> {
        Variable<GetSubnetwork>.invoke(
            name: "\(name)-subnetwork",
            function: "gcp:compute:getSubnetwork",
            arguments: [
                "name": name,
                "project": project ?? context.gcpProjectID,
                "region": (location ?? context.gcpRegion).rawValue,
            ],
            context: context
        ).output
    }
}
