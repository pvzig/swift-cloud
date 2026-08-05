import Testing

@testable import CloudCore
@testable import CloudGCP

@Suite("GCP networking and data")
struct NetworkingTests {
    @Test("Private VPC orders service networking, Cloud SQL, replicas, and Redis")
    func privateDataPlane() throws {
        let context = makeContext(stage: "production")
        let api = GCP.ProjectService(.serviceNetworking, context: context)
        let options = Resource.Options.dependsOn([api])
        let vpc = GCP.VPC("main", options: options, context: context)
        let database = GCP.SQLDatabase(
            "database",
            availability: .regional,
            vpc: vpc,
            readReplicaCount: 1,
            options: options,
            context: context
        )
        _ = GCP.Cache(
            "cache",
            vpc: vpc,
            tier: .highAvailability,
            memorySizeGB: 5,
            options: options,
            context: context
        )

        let network = try properties(type: "gcp:compute:Network", in: context)
        #expect(network["autoCreateSubnetworks"] as? Bool == false)

        let primary = try properties(
            type: "gcp:sql:DatabaseInstance",
            in: context,
            chosenName: "database"
        )
        let settings = try #require(primary["settings"] as? [String: Any])
        #expect(settings["availabilityType"] as? String == "REGIONAL")
        let ip = try #require(settings["ipConfiguration"] as? [String: Any])
        #expect(ip["ipv4Enabled"] as? Bool == false)
        #expect(ip["privateNetwork"] as? String == "${production-main.id}")
        #expect(database.readReplicas.count == 1)

        let replica = try properties(
            type: "gcp:sql:DatabaseInstance",
            in: context,
            chosenName: "database-read-replica-1"
        )
        #expect(replica["masterInstanceName"] as? String == "${production-database.name}")

        let cache = try properties(type: "gcp:redis:Instance", in: context)
        #expect(cache["tier"] as? String == "STANDARD_HA")
        #expect(cache["connectMode"] as? String == "PRIVATE_SERVICE_ACCESS")

        let connection = try resource(type: "gcp:servicenetworking:Connection", in: context)
        let dependencies = try #require(connection.pulumiProjectResources().values.first?.options?.dependsOn)
        #expect(dependencies.count == 2)
    }
}
