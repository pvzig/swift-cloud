import CloudCore

extension GCP {
    public struct DNS: DNSProvider {
        public let zone: Resource
        public let zoneName: String

        public init(
            _ name: String,
            zoneName: String,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            self.zoneName = zoneName
            let projectID =
                (options?.provider as? GCP.Provider)?.projectID
                ?? context.gcpProjectID
            zone = Resource(
                name: name,
                type: "gcp:dns:ManagedZone",
                properties: nil,
                options: options,
                context: context,
                existingId: "projects/\(projectID)/managedZones/\(name)"
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
            createRecord(type: .cname, name: name, target: target, ttl: ttl)
        }
    }
}

extension DNSProvider where Self == GCP.DNS {
    public static func gcp(
        _ name: String,
        zoneName: String,
        options: Resource.Options? = nil,
        context: Context = .current
    ) -> Self {
        .init(
            name,
            zoneName: zoneName,
            options: options,
            context: context
        )
    }
}
