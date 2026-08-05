import CloudCore

extension GCP {
    public struct DNSRecord: GCPResourceProvider, DNSProviderRecord {
        public let resource: Resource

        public var fqdn: Output<String> {
            resource.name
        }

        public init(
            zone: DNS,
            type: any Input<String>,
            name: any Input<String>,
            ttl: Duration = .seconds(300),
            records: [any Input<String>],
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            precondition(ttl >= .zero, "ttl must not be negative")
            let recordName = name.description.hasSuffix(".") ? name.description : "\(name)."
            resource = Resource(
                name: "\(zone.zone.chosenName)-\(name)-\(type)-record",
                type: "gcp:dns:RecordSet",
                properties: [
                    "project": context.gcpProjectID,
                    "managedZone": zone.zone.name,
                    "name": recordName,
                    "type": type,
                    "ttl": ttl.components.seconds,
                    "rrdatas": records,
                ],
                options: options ?? zone.zone.options,
                context: context,
                dependsOn: [zone.zone]
            )
        }
    }
}
