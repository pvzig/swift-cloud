import Testing

@testable import CloudCore
@testable import CloudGCP

@Suite("GCP managed data and lookups")
struct DataAndLookupTests {
    @Test("Firestore and Spanner encode indexes, autoscaling, schemas, IAM, and links")
    func managedData() throws {
        let context = makeContext(stage: "production")
        let identity = GCP.ServiceAccount("backend", context: context)
        let firestore = GCP.FirestoreDatabase(
            "documents",
            indexes: [
                .init(
                    collection: "messages",
                    fields: [.ascending("roomID"), .descending("createdAt")]
                )
            ],
            context: context
        )
        let archive = GCP.FirestoreDatabase(
            "archive",
            databaseID: "archive",
            context: context
        )
        let spannerInstance = GCP.Spanner.Instance(
            "global-data",
            capacity: .autoscaling(.init(minimumProcessingUnits: 100, maximumProcessingUnits: 2_000)),
            context: context
        )
        let spanner = GCP.Spanner.Database(
            "accounts",
            instance: spannerInstance,
            schema: ["CREATE TABLE Accounts (AccountId STRING(36) NOT NULL) PRIMARY KEY (AccountId)"],
            context: context
        )
        let service = GCP.CloudRunService(
            "backend",
            image: "us-docker.pkg.dev/example/backend:latest",
            serviceAccount: identity,
            context: context
        ).link([firestore, archive, spanner])

        let firestoreProperties = try properties(
            type: "gcp:firestore:Database",
            in: context,
            chosenName: "documents"
        )
        #expect(firestoreProperties["name"] as? String == "(default)")
        #expect(firestoreProperties["deleteProtectionState"] as? String == "DELETE_PROTECTION_ENABLED")
        let index = try properties(type: "gcp:firestore:Index", in: context)
        let fields = try #require(index["fields"] as? [[String: Any]])
        #expect(fields.count == 2)
        #expect(fields[1]["order"] as? String == "DESCENDING")

        let instance = try properties(type: "gcp:spanner:Instance", in: context)
        let autoscaling = try #require(instance["autoscalingConfig"] as? [String: Any])
        let limits = try #require(autoscaling["autoscalingLimits"] as? [String: Any])
        #expect(limits["maxProcessingUnits"] as? Int == 2_000)
        let database = try properties(type: "gcp:spanner:Database", in: context)
        #expect(database["deletionProtection"] as? Bool == true)
        #expect((database["ddls"] as? [String])?.count == 1)

        let projectGrants = context.store.resources.filter {
            $0.type == "gcp:projects:IAMMember"
                && $0.chosenName.contains("roles-datastore-user")
        }
        #expect(projectGrants.count == 1)
        #expect(context.store.resources.contains { $0.type == "gcp:spanner:DatabaseIAMMember" })
        #expect(service.environment.values.keys.contains("FIRESTORE_DOCUMENTS_NAME"))
        #expect(service.environment.values.keys.contains("SPANNER_ACCOUNTS_NAME"))
    }

    @Test("Project, network, subnetwork, and DNS lookups emit Pulumi invokes")
    func lookups() throws {
        let context = makeContext()
        _ = GCP.getProject(context: context)
        _ = GCP.Compute.getNetwork(name: "default", context: context)
        _ = GCP.Compute.getSubnetwork(name: "private", context: context)
        _ = GCP.DNS.getManagedZone(name: "example-zone", context: context)

        let definitions = try variableDefinitions(in: context)
        #expect(definitions.count == 4)
        let functions = definitions.values.compactMap { definition -> String? in
            guard
                let definition = definition as? [String: Any],
                let invocation = definition["fn::invoke"] as? [String: Any]
            else {
                return nil
            }
            return invocation["function"] as? String
        }
        #expect(
            Set(functions) == [
                "gcp:compute:getNetwork",
                "gcp:compute:getSubnetwork",
                "gcp:dns:getManagedZone",
                "gcp:organizations:getProject",
            ]
        )
    }
}
