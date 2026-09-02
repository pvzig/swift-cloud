import CloudCore

extension GCP {
    public struct DNS: DNSProvider {
        public let zone: Resource
        public let zoneName: String

        public init(
            _ name: String,
            zoneName: String,
            dnssecEnabled: Bool = true,
            forceDestroy: Bool = false,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            self.zoneName = zoneName
            zone = Resource(
                name: name,
                type: "gcp:dns:ManagedZone",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(context.gcpStage, name, maxLength: 63),
                    "dnsName": zoneName.hasSuffix(".") ? zoneName : "\(zoneName).",
                    "visibility": "public",
                    "dnssecConfig": ["state": dnssecEnabled ? "on" : "off"],
                    "forceDestroy": forceDestroy,
                ],
                options: options,
                context: context
            )
        }

        public func createRecord(
            type: DNSRecordType,
            name: any Input<String>,
            target: any Input<String>,
            ttl: Duration
        ) -> DNSProviderRecord {
            DNSRecord(
                zone: self,
                type: type,
                name: name,
                ttl: ttl,
                records: [target],
                options: zone.options,
                context: zone.context
            )
        }

        public func createAlias(
            name: any Input<String>,
            target: any Input<String>,
            ttl: Duration
        ) -> DNSProviderRecord {
            createRecord(type: .a, name: name, target: target, ttl: ttl)
        }
    }
}

extension DNSProvider where Self == GCP.DNS {
    public static func gcp(
        _ name: String,
        zoneName: String,
        dnssecEnabled: Bool = true,
        forceDestroy: Bool = false,
        options: Resource.Options? = nil,
        context: Context = .current
    ) -> Self {
        .init(
            name,
            zoneName: zoneName,
            dnssecEnabled: dnssecEnabled,
            forceDestroy: forceDestroy,
            options: options,
            context: context
        )
    }
}
