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

    @Test("CDN routes Cloud Run, Cloud Storage, and external origins by path")
    func multiOriginCDN() throws {
        let context = makeContext()
        let dns = GCP.DNS("example-zone", zoneName: "example.com", context: context)
        let service = GCP.CloudRunService(
            "web",
            image: "us-docker.pkg.dev/example/web:latest",
            context: context
        )
        let bucket = GCP.Bucket("assets", publicReadAccess: true, context: context)
        let cdn = GCP.CDN(
            "web-edge",
            origins: [
                .cloudRun(service, path: "*"),
                .bucket(bucket, path: "/assets/*"),
                .external(hostname: "images.example.net", path: "/images/*"),
            ],
            domainName: .init(hostname: "www.example.com", dns: dns),
            context: context
        )

        #expect(cdn.url.description == "https://www.example.com")
        #expect(cdn.originBackends.count == 3)
        #expect(cdn.networkEndpointGroups.count == 2)
        #expect(cdn.networkEndpoints.count == 1)
        #expect(context.store.resources.contains { $0.type == "gcp:compute:BackendBucket" })
        #expect(context.store.resources.contains { $0.type == "gcp:compute:GlobalNetworkEndpoint" })
        #expect(context.store.resources.contains { $0.type == "gcp:storage:BucketIAMMember" })

        let urlMap = try properties(type: "gcp:compute:URLMap", in: context)
        #expect(urlMap["defaultService"] as? String == "${testing-web-edge-origin-1-backend.id}")
        let matchers = try #require(urlMap["pathMatchers"] as? [[String: Any]])
        let matcher = try #require(matchers.first)
        let rules = try #require(matcher["pathRules"] as? [[String: Any]])
        #expect(rules.count == 2)
        #expect(rules.contains { $0["paths"] as? [String] == ["/assets/*"] })
        #expect(rules.contains { $0["paths"] as? [String] == ["/images/*"] })

        let externalBackend = try properties(
            type: "gcp:compute:BackendService",
            in: context,
            chosenName: "web-edge-origin-3-backend"
        )
        #expect(externalBackend["protocol"] as? String == "HTTPS")
        #expect(externalBackend["customRequestHeaders"] as? [String] == ["Host: images.example.net"])
    }

    @Test("Serverless network endpoint groups follow the Cloud Run service's region")
    func serverlessEndpointGroupRegion() throws {
        // A serverless NEG must live in the same region as its Cloud Run service,
        // which is not necessarily the project's default region.
        let context = makeContext()
        let dns = GCP.DNS("example-zone", zoneName: "example.com", context: context)
        let service = GCP.CloudRunService(
            "api",
            image: "us-docker.pkg.dev/example/api:latest",
            location: .europeWest1,
            context: context
        )
        _ = GCP.HTTPSLoadBalancer(
            "api-edge",
            service: service,
            domainName: .init(hostname: "api.example.com", dns: dns),
            context: context
        )
        _ = GCP.CDN(
            "api-cdn",
            origins: [.cloudRun(service, path: "*")],
            domainName: .init(hostname: "cdn.example.com", dns: dns),
            context: context
        )

        #expect(context.gcpRegion.rawValue == "us-east1")
        let loadBalancerGroup = try properties(
            type: "gcp:compute:RegionNetworkEndpointGroup",
            in: context,
            chosenName: "api-edge-neg"
        )
        #expect(loadBalancerGroup["region"] as? String == "${testing-api.location}")

        let cdnGroup = try properties(
            type: "gcp:compute:RegionNetworkEndpointGroup",
            in: context,
            chosenName: "api-cdn-origin-1-neg"
        )
        #expect(cdnGroup["region"] as? String == "${testing-api.location}")
    }

    @Test("An explicit edge location still overrides the service region")
    func explicitEndpointGroupRegion() throws {
        let context = makeContext()
        let dns = GCP.DNS("example-zone", zoneName: "example.com", context: context)
        let service = GCP.CloudRunService(
            "api",
            image: "us-docker.pkg.dev/example/api:latest",
            context: context
        )
        _ = GCP.HTTPSLoadBalancer(
            "api-edge",
            service: service,
            domainName: .init(hostname: "api.example.com", dns: dns),
            location: .usWest1,
            context: context
        )

        let group = try properties(type: "gcp:compute:RegionNetworkEndpointGroup", in: context)
        #expect(group["region"] as? String == "us-west1")
    }
}
