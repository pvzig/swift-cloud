import CloudCore

extension GCP {
    public struct DNSRecord: GCPResourceProvider, DNSProviderRecord {
        public let resource: Resource
        public let fqdn: Output<String>

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
            let nameWithoutTrailingDot: any Input<String>
            if let literalName = name as? String {
                nameWithoutTrailingDot =
                    literalName.hasSuffix(".")
                    ? String(literalName.dropLast())
                    : literalName
            } else {
                nameWithoutTrailingDot =
                    Strings.trimSuffix(
                        name,
                        suffix: ".",
                        name: "\(zone.zone.chosenName)-\(digest(name, type))-record-name",
                        context: context
                    ).result
            }
            fqdn = "\(nameWithoutTrailingDot)"
            resource = Resource(
                name: "\(zone.zone.chosenName)-\(name)-\(type)-record",
                type: "gcp:dns:RecordSet",
                properties: [
                    "project": context.gcpProjectID,
                    "managedZone": zone.zone.name,
                    "name": "\(fqdn)." as Output<String>,
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
