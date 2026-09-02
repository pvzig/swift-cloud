import CloudCore

extension GCP {
    /// A Cloud SQL instance and one logical database.
    ///
    /// Passwordless IAM users can be linked to the database. Password-bearing
    /// users remain outside this component because Swift Cloud does not expose
    /// a secret input primitive suitable for generated Pulumi YAML.
    public struct SQLDatabase: GCPComponent {
        public let engine: Engine
        public let instance: Resource
        public let database: Resource
        public let readReplicas: [Resource]
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
            pointInTimeRecoveryEnabled: Bool = true,
            availability: Availability = .zonal,
            iamAuthenticationEnabled: Bool = true,
            vpc: VPC? = nil,
            publicIPv4: Bool? = nil,
            readReplicaCount: Int = 0,
            deletionProtection: Bool? = nil,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            precondition(readReplicaCount >= 0, "readReplicaCount must not be negative")
            precondition(
                readReplicaCount == 0 || backupsEnabled,
                "read replicas require backups"
            )
            // MySQL replication is driven by the binary log, which this component
            // only enables alongside point-in-time recovery.
            precondition(
                readReplicaCount == 0 || engine.isMySQL == false || pointInTimeRecoveryEnabled,
                "MySQL read replicas require pointInTimeRecoveryEnabled so binary logging is on"
            )
            self.engine = engine
            self.databaseName = databaseName ?? tokenize(context.gcpStage, "app", maxLength: 63)
            let ipv4Enabled = publicIPv4 ?? (vpc == nil)
            let privateDependencies: [any ResourceProvider] =
                vpc.map { [$0.privateServiceConnection] } ?? []

            instance = Resource(
                name: name,
                type: "gcp:sql:DatabaseInstance",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(context.gcpStage, name, maxLength: 98),
                    "region": (location ?? context.gcpRegion).rawValue,
                    "databaseVersion": engine.databaseVersion,
                    "settings": [
                        "tier": tier,
                        "availabilityType": availability.rawValue,
                        "databaseFlags": iamAuthenticationEnabled
                            ? [
                                [
                                    "name": engine.iamAuthenticationFlag,
                                    "value": "on",
                                ]
                            ]
                            : [],
                        "ipConfiguration": [
                            "ipv4Enabled": ipv4Enabled,
                            "privateNetwork": AnyEncodable(vpc?.network.id),
                            "enablePrivatePathForGoogleCloudServices": vpc != nil,
                        ],
                        "backupConfiguration": [
                            "enabled": backupsEnabled,
                            "pointInTimeRecoveryEnabled": engine.isPostgres
                                ? backupsEnabled && pointInTimeRecoveryEnabled
                                : nil,
                            "binaryLogEnabled": engine.isMySQL
                                ? backupsEnabled && pointInTimeRecoveryEnabled
                                : nil,
                        ],
                    ],
                    "deletionProtection": deletionProtection ?? context.isProduction,
                ],
                options: options,
                context: context,
                dependsOn: privateDependencies
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

            let primaryInstance = instance
            readReplicas = (0..<readReplicaCount).map { index in
                Resource(
                    name: "\(name)-read-replica-\(index + 1)",
                    type: "gcp:sql:DatabaseInstance",
                    properties: [
                        "project": context.gcpProjectID,
                        "name": tokenize(
                            context.gcpStage,
                            name,
                            "read",
                            "\(index + 1)",
                            maxLength: 98
                        ),
                        "region": (location ?? context.gcpRegion).rawValue,
                        "databaseVersion": engine.databaseVersion,
                        "masterInstanceName": primaryInstance.name,
                        "settings": [
                            "tier": tier,
                            "databaseFlags": iamAuthenticationEnabled
                                ? [
                                    [
                                        "name": engine.iamAuthenticationFlag,
                                        "value": "on",
                                    ]
                                ]
                                : [],
                            "ipConfiguration": [
                                "ipv4Enabled": ipv4Enabled,
                                "privateNetwork": AnyEncodable(vpc?.network.id),
                                "enablePrivatePathForGoogleCloudServices": vpc != nil,
                            ],
                        ],
                        "deletionProtection": deletionProtection ?? context.isProduction,
                    ],
                    options: options,
                    context: context,
                    dependsOn: [primaryInstance] + privateDependencies
                )
            }
        }
    }
}

extension GCP.SQLDatabase {
    public struct Engine: Sendable {
        public let databaseVersion: String
        public let port: Int
        public let scheme: String

        fileprivate var isPostgres: Bool {
            scheme == "postgres"
        }

        fileprivate var isMySQL: Bool {
            scheme == "mysql"
        }

        fileprivate var iamAuthenticationFlag: String {
            isPostgres ? "cloudsql.iam_authentication" : "cloudsql_iam_authentication"
        }

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

    public enum Availability: String, Sendable {
        case zonal = "ZONAL"
        case regional = "REGIONAL"
    }
}

extension GCP.SQLDatabase {
    /// Grants the Cloud Run identity permission to use the Cloud SQL connector.
    @discardableResult
    public func allowConnections(from serviceAccount: GCP.ServiceAccount) -> Self {
        _ = connectionAccessGrants(for: serviceAccount)
        return self
    }

    private func connectionAccessGrants(
        for serviceAccount: GCP.ServiceAccount
    ) -> [any ResourceProvider] {
        [
            serviceAccount.projectRole(.cloudSQLClient),
            serviceAccount.projectRole(.cloudSQLInstanceUser),
            createIAMUser(for: serviceAccount),
        ]
    }

    @discardableResult
    public func createIAMUser(for serviceAccount: GCP.ServiceAccount) -> Resource {
        let resourceName = "\(instance.chosenName)-iam-user-\(serviceAccount.resource.chosenName)"
        if let existing = instance.context.store.resource(
            type: "gcp:sql:User",
            chosenName: resourceName
        ) {
            return existing
        }
        let username = Strings.trimSuffix(
            serviceAccount.email,
            suffix: ".gserviceaccount.com",
            name: "\(instance.chosenName)-\(serviceAccount.resource.chosenName)-iam-username",
            context: instance.context
        ).result
        return Resource(
            name: resourceName,
            type: "gcp:sql:User",
            properties: [
                "project": instance.context.gcpProjectID,
                "name": username,
                "instance": instance.name,
                "type": "CLOUD_IAM_SERVICE_ACCOUNT",
            ],
            options: instance.options,
            context: instance.context,
            dependsOn: [instance, serviceAccount]
        )
    }
}

extension GCP.SQLDatabase: GCPLinkable {
    public func grantAccess(to serviceAccount: GCP.ServiceAccount) {
        _ = accessGrants(to: serviceAccount)
    }

    public var actions: [String] {
        [
            GCP.IAMRole.cloudSQLClient.rawValue,
            GCP.IAMRole.cloudSQLInstanceUser.rawValue,
        ]
    }

    public var resources: [Output<String>] {
        [instance.id]
    }

    public var properties: LinkProperties? {
        .init(
            type: "sqldb",
            name: instance.chosenName,
            properties: [
                "connectionName": connectionName,
                "databaseName": databaseName,
                "port": "\(port)",
                "scheme": engine.scheme,
            ]
        )
    }

    public func accessGrants(to serviceAccount: GCP.ServiceAccount) -> [any ResourceProvider] {
        connectionAccessGrants(for: serviceAccount)
    }
}
