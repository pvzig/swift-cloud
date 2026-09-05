import CloudCore

extension GCP {
    /// A custom-mode VPC with one regional subnet and private service access.
    public struct VPC: GCPComponent {
        public let network: Resource
        public let subnetwork: Resource
        public let privateAddress: Resource
        public let privateServiceConnection: Resource
        public let location: Region

        public var name: Output<String> {
            network.name
        }

        public init(
            _ name: String,
            location: Region? = nil,
            subnetCIDR: String = "10.0.0.0/20",
            privateServicePrefixLength: Int = 16,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            precondition(
                (8...29).contains(privateServicePrefixLength),
                "privateServicePrefixLength must be between 8 and 29"
            )

            self.location = GCP.resolvedRegion(location, options: options, context: context)

            network = Resource(
                name: name,
                type: "gcp:compute:Network",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(context.gcpStage, name, maxLength: 63),
                    "autoCreateSubnetworks": false,
                    "routingMode": "REGIONAL",
                ],
                options: options,
                context: context
            )

            subnetwork = Resource(
                name: "\(name)-subnet",
                type: "gcp:compute:Subnetwork",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(context.gcpStage, name, "subnet", maxLength: 63),
                    "region": self.location.rawValue,
                    "network": network.id,
                    "ipCidrRange": subnetCIDR,
                    "privateIpGoogleAccess": true,
                ],
                options: options,
                context: context
            )

            privateAddress = Resource(
                name: "\(name)-private-services-range",
                type: "gcp:compute:GlobalAddress",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(context.gcpStage, name, "private-services", maxLength: 63),
                    "purpose": "VPC_PEERING",
                    "addressType": "INTERNAL",
                    "prefixLength": privateServicePrefixLength,
                    "network": network.id,
                ],
                options: options,
                context: context
            )

            privateServiceConnection = Resource(
                name: "\(name)-private-services-connection",
                type: "gcp:servicenetworking:Connection",
                properties: [
                    "network": network.id,
                    "service": "servicenetworking.googleapis.com",
                    "reservedPeeringRanges": [privateAddress.name],
                ],
                options: options,
                context: context,
                dependsOn: [privateAddress]
            )
        }
    }
}
