import CloudCore

extension GCP.DNS {
    public struct GetManagedZone: Sendable {
        public let dnsName: String
        public let id: String
        public let managedZoneId: String
        public let name: String
        public let nameServers: [String]
        public let project: String
        public let visibility: String
    }

    public static func getManagedZone(
        name: any Input<String>,
        project: String? = nil,
        context: Context = .current
    ) -> Output<GetManagedZone> {
        let project = project ?? context.gcpProjectID
        return Variable<GetManagedZone>.invoke(
            name: "\(name)-\(digest(name, project))-managed-zone",
            function: "gcp:dns:getManagedZone",
            arguments: [
                "name": name,
                "project": project,
            ],
            context: context
        ).output
    }
}
