import CloudCore

extension GCP {
    /// A Cloud SQL instance and one logical database.
    ///
    /// Database users are deliberately separate from this component. Swift
    /// Cloud does not yet expose a secret input primitive suitable for placing
    /// password material in generated Pulumi YAML.
    public struct SQLDatabase: GCPComponent {
        public let engine: Engine
        public let instance: Resource
        public let database: Resource
        public let databaseName: String

        public var name: Output<String> {
            database.name
        }

        public var connectionName: Output<String> {
            instance.output.keyPath("connectionName")
        }

        public var port: Int {
            engine.port
        }

        public init(
            _ name: String,
            engine: Engine = .postgres16,
            databaseName: String? = nil,
            location: Region? = nil,
            tier: String = "db-custom-1-3840",
            backupsEnabled: Bool = true,
            deletionProtection: Bool? = nil,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            self.engine = engine
            self.databaseName = databaseName ?? tokenize(context.stage, "app")

            instance = Resource(
                name: name,
                type: "gcp:sql:DatabaseInstance",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(context.stage, name),
                    "region": (location ?? context.gcpRegion).rawValue,
                    "databaseVersion": engine.databaseVersion,
                    "settings": [
                        "tier": tier,
                        "ipConfiguration": [
                            // Cloud Run's /cloudsql connector still requires
                            // the instance to have either public or private IP.
                            // No authorized network is created.
                            "ipv4Enabled": true
                        ],
                        "backupConfiguration": [
                            "enabled": backupsEnabled
                        ],
                    ],
                    "deletionProtection": deletionProtection ?? context.isProduction,
                ],
                options: options,
                context: context
            )

            database = Resource(
                name: "\(name)-database",
                type: "gcp:sql:Database",
                properties: [
                    "project": context.gcpProjectID,
                    "name": self.databaseName,
                    "instance": instance.name,
                ],
                options: options,
                context: context,
                dependsOn: [instance]
            )
        }
    }
}

extension GCP.SQLDatabase {
    public struct Engine: Sendable {
        public let databaseVersion: String
        public let port: Int
        public let scheme: String

        public init(databaseVersion: String, port: Int, scheme: String) {
            self.databaseVersion = databaseVersion
            self.port = port
            self.scheme = scheme
        }

        public static let mysql8 = Self(
            databaseVersion: "MYSQL_8_0",
            port: 3306,
            scheme: "mysql"
        )

        public static let postgres15 = Self(
            databaseVersion: "POSTGRES_15",
            port: 5432,
            scheme: "postgres"
        )

        public static let postgres16 = Self(
            databaseVersion: "POSTGRES_16",
            port: 5432,
            scheme: "postgres"
        )

        public static let postgres17 = Self(
            databaseVersion: "POSTGRES_17",
            port: 5432,
            scheme: "postgres"
        )
    }
}

extension GCP.SQLDatabase {
    /// Grants the Cloud Run identity permission to use the Cloud SQL connector.
    @discardableResult
    public func allowConnections(from serviceAccount: GCP.ServiceAccount) -> Self {
        serviceAccount.grantProjectRole(.cloudSQLClient)
        return self
    }
}
