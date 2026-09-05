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
        public let iamAuthenticationEnabled: Bool

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
            edition: Edition = .enterprise,
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
                publicIPv4 != false || vpc != nil,
                "disabling public IPv4 requires a VPC for private connectivity"
            )
            precondition(
                availability != .regional || backupsEnabled,
                "regional Cloud SQL instances require backups"
            )
            precondition(
                availability != .regional || engine.isMySQL == false || pointInTimeRecoveryEnabled,
                "regional MySQL instances require pointInTimeRecoveryEnabled for binary logging"
            )
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
            self.iamAuthenticationEnabled = iamAuthenticationEnabled
            let ipv4Enabled = publicIPv4 ?? (vpc == nil)
            let privateDependencies: [any ResourceProvider] =
                vpc.map { [$0.privateServiceConnection] } ?? []

            instance = Resource(
                name: name,
                type: "gcp:sql:DatabaseInstance",
                properties: [
                    "project": context.gcpProjectID,
                    "region": GCP.resolvedRegion(location, options: options, context: context).rawValue,
                    "databaseVersion": engine.databaseVersion,
                    "settings": [
                        "tier": tier,
                        "edition": edition.rawValue,
                        "availabilityType": availability.rawValue,
                        "databaseFlags": iamAuthenticationEnabled
                            ? [
                                [
                                    "name": engine.iamAuthenticationFlag,
                                    "value": "on",
                                ]
                            ]
                            : nil,
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
                        "region": GCP.resolvedRegion(
                            location,
                            options: options,
                            context: context
                        ).rawValue,
                        "databaseVersion": engine.databaseVersion,
                        "masterInstanceName": primaryInstance.name,
                        "settings": [
                            "tier": tier,
                            "edition": edition.rawValue,
                            "databaseFlags": iamAuthenticationEnabled
                                ? [
                                    [
                                        "name": engine.iamAuthenticationFlag,
                                        "value": "on",
                                    ]
                                ]
                                : nil,
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
            family == .postgres
        }

        fileprivate var isMySQL: Bool {
            family == .mysql
        }

        fileprivate var iamAuthenticationFlag: String {
            isPostgres ? "cloudsql.iam_authentication" : "cloudsql_iam_authentication"
        }

        public init(databaseVersion: String, port: Int, scheme: String) {
            precondition(
                databaseVersion.hasPrefix("POSTGRES_") || databaseVersion.hasPrefix("MYSQL_"),
                "Cloud SQL supports PostgreSQL or MySQL database versions"
            )
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

        private enum Family {
            case mysql
            case postgres
        }

        private var family: Family {
            databaseVersion.hasPrefix("POSTGRES_") ? .postgres : .mysql
        }
    }

    public enum Availability: String, Equatable, Sendable {
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
        var grants: [any ResourceProvider] = [serviceAccount.projectRole(.cloudSQLClient)]
        if iamAuthenticationEnabled {
            grants.append(serviceAccount.projectRole(.cloudSQLInstanceUser))
            grants.append(createIAMUser(for: serviceAccount))
        }
        return grants
    }

    @discardableResult
    public func createIAMUser(for serviceAccount: GCP.ServiceAccount) -> Resource {
        precondition(
            iamAuthenticationEnabled,
            "IAM database users require iamAuthenticationEnabled"
        )
        let resourceName = "\(instance.chosenName)-iam-user-\(serviceAccount.resource.chosenName)"
        // PostgreSQL omits this suffix; MySQL's creation API requires the full email.
        let username =
            if engine.isPostgres {
                Strings.trimSuffix(
                    serviceAccount.email,
                    suffix: ".gserviceaccount.com",
                    name: "\(instance.chosenName)-\(serviceAccount.resource.chosenName)-iam-username",
                    context: instance.context
                ).result
            } else {
                serviceAccount.email
            }
        return GCP.sharedResource(
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
    public var actions: [String] {
        var actions = [GCP.IAMRole.cloudSQLClient.rawValue]
        if iamAuthenticationEnabled {
            actions.append(GCP.IAMRole.cloudSQLInstanceUser.rawValue)
        }
        return actions
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
