import Testing

@testable import CloudCore
@testable import CloudGCP

@Suite("GCP Cloud SQL")
struct SQLDatabaseTests {
    @Test("Cloud SQL emits a protected PostgreSQL instance and logical database")
    func databaseShape() throws {
        let context = makeContext(stage: "production")
        let serviceAccount = GCP.ServiceAccount("backend", context: context)
        let database = GCP.SQLDatabase(
            "main",
            engine: .postgres16,
            databaseName: "app",
            context: context
        ).allowConnections(from: serviceAccount)

        #expect(database.connectionName.description == "${production-main.connectionName}")
        #expect(database.port == 5432)

        let instance = try properties(type: "gcp:sql:DatabaseInstance", in: context)
        #expect(instance["databaseVersion"] as? String == "POSTGRES_16")
        #expect(instance["name"] == nil)
        #expect(instance["region"] as? String == "us-east1")
        #expect(instance["deletionProtection"] as? Bool == true)

        let settings = try #require(instance["settings"] as? [String: Any])
        #expect(settings["tier"] as? String == "db-custom-1-3840")
        let ipConfiguration = try #require(settings["ipConfiguration"] as? [String: Any])
        #expect(ipConfiguration["ipv4Enabled"] as? Bool == true)

        let logicalDatabase = try properties(type: "gcp:sql:Database", in: context)
        #expect(logicalDatabase["name"] as? String == "app")
        #expect(logicalDatabase["instance"] as? String == "${production-main.name}")

        let role = try properties(type: "gcp:projects:IAMMember", in: context)
        #expect(role["role"] as? String == "roles/cloudsql.client")
        #expect(role["member"] as? String == "serviceAccount:${production-backend-service-account.email}")

        let user = try properties(type: "gcp:sql:User", in: context)
        #expect(user["type"] as? String == "CLOUD_IAM_SERVICE_ACCOUNT")
        #expect(
            user["name"] as? String
                == "${production-main-backend-service-account-iam-username.result}"
        )
    }

    @Test("Engine family comes from databaseVersion, not the connection scheme")
    func engineFamily() throws {
        let context = makeContext()
        _ = GCP.SQLDatabase(
            "main",
            engine: .init(
                databaseVersion: "POSTGRES_16",
                port: 5432,
                scheme: "postgresql"
            ),
            context: context
        )

        let instance = try properties(type: "gcp:sql:DatabaseInstance", in: context)
        let settings = try #require(instance["settings"] as? [String: Any])
        let flags = try #require(settings["databaseFlags"] as? [[String: Any]])
        #expect(flags.first?["name"] as? String == "cloudsql.iam_authentication")
    }

    @Test("Password-auth databases do not create invalid IAM database users")
    func passwordAuthenticationLink() {
        let context = makeContext()
        let runtime = GCP.ServiceAccount("backend", context: context)
        let database = GCP.SQLDatabase(
            "main",
            iamAuthenticationEnabled: false,
            context: context
        )
        _ = GCP.CloudRunService(
            "backend",
            image: "us-docker.pkg.dev/example/backend:latest",
            serviceAccount: runtime,
            context: context
        ).link(database)

        #expect(context.store.resources.contains { $0.type == "gcp:sql:User" } == false)
        let roles = context.store.resources.filter { $0.type == "gcp:projects:IAMMember" }
        #expect(roles.count == 1)
        #expect(database.actions == ["roles/cloudsql.client"])
    }

    @Test("Cloud SQL rejects configurations without a viable network path")
    func missingNetworkPath() async {
        await #expect(processExitsWith: .failure) {
            _ = GCP.SQLDatabase(
                "main",
                publicIPv4: false,
                context: makeContext()
            )
        }
    }

    @Test("Regional Cloud SQL requires backups")
    func regionalBackups() async {
        await #expect(processExitsWith: .failure) {
            _ = GCP.SQLDatabase(
                "main",
                backupsEnabled: false,
                availability: .regional,
                context: makeContext()
            )
        }
    }

    @Test("Regional MySQL requires binary logging")
    func regionalMySQLBinaryLogging() async {
        await #expect(processExitsWith: .failure) {
            _ = GCP.SQLDatabase(
                "main",
                engine: .mysql8,
                pointInTimeRecoveryEnabled: false,
                availability: .regional,
                context: makeContext()
            )
        }
    }
}
