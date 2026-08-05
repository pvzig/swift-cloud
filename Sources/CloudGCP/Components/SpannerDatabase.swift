import CloudCore

extension GCP.Spanner {
    /// A Spanner database with an optional initial schema.
    public struct Database: GCPComponent {
        public let database: Resource
        public let instance: Instance

        public var name: Output<String> {
            database.name
        }

        public init(
            _ name: String,
            instance: Instance,
            dialect: Dialect = .googleSQL,
            schema: [String] = [],
            versionRetentionPeriod: String = "1h",
            deletionProtection: Bool? = nil,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            self.instance = instance
            database = Resource(
                name: name,
                type: "gcp:spanner:Database",
                properties: [
                    "project": context.gcpProjectID,
                    "instance": instance.name,
                    "name": tokenize(context.stage, name, maxLength: 30),
                    "databaseDialect": dialect.rawValue,
                    "ddls": schema,
                    "versionRetentionPeriod": versionRetentionPeriod,
                    "deletionProtection": deletionProtection ?? context.isProduction,
                ],
                options: options,
                context: context,
                dependsOn: [instance]
            )
        }
    }
}

extension GCP.Spanner.Database {
    public enum Dialect: String, Sendable {
        case googleSQL = "GOOGLE_STANDARD_SQL"
        case postgreSQL = "POSTGRESQL"
    }
}

extension GCP.Spanner.Database: GCPLinkable {
    public var actions: [String] {
        [GCP.IAMRole.spannerDatabaseUser.rawValue]
    }

    public var resources: [Output<String>] {
        [database.id]
    }

    public var properties: LinkProperties? {
        .init(
            type: "spanner",
            name: database.chosenName,
            properties: [
                "name": name,
                "instance": instance.name,
                "project_id": database.context.gcpProjectID,
            ]
        )
    }

    public func grantAccess(to serviceAccount: GCP.ServiceAccount) {
        _ = Resource(
            name: "\(database.chosenName)-database-user-\(serviceAccount.resource.chosenName)",
            type: "gcp:spanner:DatabaseIAMMember",
            properties: [
                "project": database.context.gcpProjectID,
                "instance": instance.name,
                "database": name,
                "role": GCP.IAMRole.spannerDatabaseUser.rawValue,
                "member": serviceAccount.member,
            ],
            options: database.options,
            context: database.context
        )
    }
}
