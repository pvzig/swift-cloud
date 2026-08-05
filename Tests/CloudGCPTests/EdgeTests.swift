import Testing

@testable import CloudCore
@testable import CloudGCP

@Suite("GCP edge")
struct EdgeTests {
    @Test("Cloud Run HTTPS load balancer emits managed TLS, DNS, and CDN resources")
    func loadBalancer() throws {
        let context = makeContext()
        let dns = GCP.DNS("example-zone", zoneName: "example.com", context: context)
        let domain = DomainName(hostname: "api.example.com", dns: dns)
        let service = GCP.CloudRunService(
            "api",
            image: "us-docker.pkg.dev/example/api:latest",
            ingress: .internalLoadBalancer,
            context: context
        )
        let loadBalancer = GCP.HTTPSLoadBalancer(
            "api-edge",
            service: service,
            domainName: domain,
            cdn: .enabled(),
            context: context
        )

        #expect(loadBalancer.url.description == "https://api.example.com")
        let backend = try properties(type: "gcp:compute:BackendService", in: context)
        #expect(backend["enableCdn"] as? Bool == true)
        #expect(backend["loadBalancingScheme"] as? String == "EXTERNAL_MANAGED")

        let certificate = try properties(type: "gcp:compute:ManagedSslCertificate", in: context)
        let managed = try #require(certificate["managed"] as? [String: Any])
        #expect(managed["domains"] as? [String] == ["api.example.com"])

        let record = try properties(type: "gcp:dns:RecordSet", in: context)
        #expect(record["type"] as? String == "A")
        #expect(record["rrdatas"] as? [String] == ["${testing-api-edge-address.address}"])
        #expect(context.store.resources.contains { $0.type == "gcp:cloudrunv2:ServiceIamMember" })
    }
}
