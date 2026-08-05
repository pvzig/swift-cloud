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
}
