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

    @Test("Firewall and Cloud NAT encode private-network controls")
    func firewallAndNAT() throws {
        let context = makeContext()
        let vpc = GCP.VPC("main", context: context)
        _ = GCP.FirewallRule(
            "allow-health-checks",
            vpc: vpc,
            action: .allow([.tcp(["8080", "8443"])]),
            sourceRanges: ["35.191.0.0/16", "130.211.0.0/22"],
            targetTags: ["backend"],
            priority: 900,
            context: context
        )
        _ = GCP.NATGateway(
            "outbound",
            vpc: vpc,
            minimumPortsPerVM: 128,
            logging: .all,
            context: context
        )

        let firewall = try properties(type: "gcp:compute:Firewall", in: context)
        #expect(firewall["direction"] as? String == "INGRESS")
        #expect(firewall["priority"] as? Int == 900)
        #expect(firewall["sourceRanges"] as? [String] == ["35.191.0.0/16", "130.211.0.0/22"])
        let allows = try #require(firewall["allows"] as? [[String: Any]])
        #expect(allows.first?["protocol"] as? String == "tcp")
        #expect(allows.first?["ports"] as? [String] == ["8080", "8443"])

        let router = try properties(type: "gcp:compute:Router", in: context)
        #expect(router["network"] as? String == "${testing-main.id}")
        let nat = try properties(type: "gcp:compute:RouterNat", in: context)
        #expect(nat["natIpAllocateOption"] as? String == "AUTO_ONLY")
        #expect(nat["sourceSubnetworkIpRangesToNat"] as? String == "ALL_SUBNETWORKS_ALL_IP_RANGES")
        #expect(nat["minPortsPerVm"] as? Int == 128)
        let logging = try #require(nat["logConfig"] as? [String: Any])
        #expect(logging["enable"] as? Bool == true)
        #expect(logging["filter"] as? String == "ALL")
    }
}
