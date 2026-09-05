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
        #expect(backend["timeoutSec"] == nil)
        let policy = try #require(backend["cdnPolicy"] as? [String: Any])
        #expect(policy["signedUrlCacheMaxAgeSec"] as? Int == 0)

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
            ingress: .internalLoadBalancer,
            context: context
        )
        let bucket = GCP.Bucket("assets", publicReadAccess: true, context: context)
        let cdn = GCP.CDN(
            "web-edge",
            origins: [
                .cloudRun(service, path: "*"),
                .bucket(bucket, path: "/assets"),
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
            ingress: .internalLoadBalancer,
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

    @Test("The load balancer always follows the service region")
    func loadBalancerServiceRegion() throws {
        let context = makeContext()
        let dns = GCP.DNS("example-zone", zoneName: "example.com", context: context)
        let service = GCP.CloudRunService(
            "api",
            image: "us-docker.pkg.dev/example/api:latest",
            location: .usWest1,
            ingress: .internalLoadBalancer,
            context: context
        )
        _ = GCP.HTTPSLoadBalancer(
            "api-edge",
            service: service,
            domainName: .init(hostname: "api.example.com", dns: dns),
            context: context
        )

        let group = try properties(type: "gcp:compute:RegionNetworkEndpointGroup", in: context)
        #expect(group["region"] as? String == "${testing-api.location}")
    }

    @Test("Edge physical names include suffixes within the Compute limit")
    func physicalNameLimits() throws {
        let context = makeContext(stage: "12345-improve-billing-dashboard-reports")
        let dns = GCP.DNS("customer-application-zone", zoneName: "example.com", context: context)
        let service = GCP.CloudRunService(
            "customer-facing-application-service",
            image: "us-docker.pkg.dev/example/application:latest",
            ingress: .internalLoadBalancer,
            context: context
        )
        _ = GCP.CDN(
            "customer-facing-application-distribution",
            origins: [
                .cloudRun(service, path: "*"),
                .external(hostname: "images.example.com", path: "/images/*"),
            ],
            domainName: .init(hostname: "www.example.com", dns: dns),
            context: context
        )
        _ = GCP.HTTPSLoadBalancer(
            "customer-facing-application-load-balancer",
            service: service,
            domainName: .init(hostname: "api.example.com", dns: dns),
            context: context
        )

        for computeResource in context.store.resources where computeResource.type.hasPrefix("gcp:compute:") {
            let resourceProperties = try properties(of: computeResource)
            if let physicalName = resourceProperties["name"] as? String {
                #expect(physicalName.count <= 63)
            }
        }
    }

    @Test("DNS records normalize dynamic trailing dots and expose a dot-free FQDN")
    func dynamicDNSRecordName() throws {
        let context = makeContext()
        let dns = GCP.DNS("example-zone", zoneName: "example.com", context: context)
        let dynamicName = Output<String>(
            prefix: "",
            root: "managed-zone",
            path: [.property("dnsName")]
        )
        let record = GCP.DNSRecord(
            zone: dns,
            type: "A",
            name: dynamicName,
            records: ["192.0.2.1"],
            context: context
        )

        let variableName = "testing-example-zone-\(digest(dynamicName, "A"))-record-name"
        #expect(record.fqdn.description == "${\(variableName).result}")
        let recordProperties = try properties(type: "gcp:dns:RecordSet", in: context)
        #expect(recordProperties["name"] as? String == "${\(variableName).result}.")

        let secondName = Output<String>(
            prefix: "",
            root: "second-zone",
            path: [.property("dnsName")]
        )
        _ = GCP.DNSRecord(
            zone: dns,
            type: "A",
            name: secondName,
            records: ["192.0.2.2"],
            context: context
        )

        let definitions = try variableDefinitions(in: context)
        #expect(definitions.count == 2)
        let definition = try #require(definitions[variableName] as? [String: Any])
        let invocation = try #require(definition["fn::invoke"] as? [String: Any])
        #expect(invocation["function"] as? String == "str:trimSuffix")

        let literalContext = makeContext()
        let literalDNS = GCP.DNS(
            "literal-zone",
            zoneName: "example.com",
            context: literalContext
        )
        let literalRecord = GCP.DNSRecord(
            zone: literalDNS,
            type: "A",
            name: "api.example.com.",
            records: ["192.0.2.2"],
            context: literalContext
        )
        #expect(literalRecord.fqdn.description == "api.example.com")
        let literalProperties = try properties(type: "gcp:dns:RecordSet", in: literalContext)
        #expect(literalProperties["name"] as? String == "api.example.com.")
    }

    @Test("GCP DNS references an existing zone and emits CNAME aliases")
    func existingDNSZoneAndAlias() throws {
        let context = makeContext()
        let dns = GCP.DNS("example-zone", zoneName: "example.com", context: context)
        _ = dns.createAlias(
            name: "docs.example.com",
            target: "ghs.googlehosted.com",
            ttl: .seconds(300)
        )

        let zone = try #require(dns.zone.pulumiProjectResources().values.first)
        #expect(zone.get?.id == "projects/example-project/managedZones/example-zone")
        #expect(zone.properties == nil)
        let record = try properties(type: "gcp:dns:RecordSet", in: context)
        #expect(record["type"] as? String == "CNAME")
    }

    @Test("Edge resources request an A record from every DNS provider")
    func edgeUsesAddressRecord() {
        let context = makeContext()
        let dns = RecordingDNSProvider()
        let service = GCP.CloudRunService(
            "api",
            image: "us-docker.pkg.dev/example/api:latest",
            ingress: .internalLoadBalancer,
            context: context
        )
        _ = GCP.HTTPSLoadBalancer(
            "api-edge",
            service: service,
            domainName: .init(hostname: "api.example.com", dns: dns),
            context: context
        )

        #expect(dns.recordTypes == ["A"])
    }

    @Test("Edge components reject directly reachable Cloud Run services")
    func directIngressIsRejected() async {
        await #expect(processExitsWith: .failure) {
            let context = makeContext()
            let service = GCP.CloudRunService(
                "api",
                image: "us-docker.pkg.dev/example/api:latest",
                context: context
            )
            _ = GCP.HTTPSLoadBalancer(
                "api-edge",
                service: service,
                domainName: .init(
                    hostname: "api.example.com",
                    dns: GCP.DNS("example-zone", zoneName: "example.com", context: context)
                ),
                context: context
            )
        }
    }

    @Test("Managed certificate names change with the hostname")
    func certificateRevisionName() throws {
        func certificateName(hostname: String) throws -> String {
            let context = makeContext()
            let service = GCP.CloudRunService(
                "api",
                image: "us-docker.pkg.dev/example/api:latest",
                ingress: .internalLoadBalancer,
                context: context
            )
            _ = GCP.HTTPSLoadBalancer(
                "api-edge",
                service: service,
                domainName: .init(
                    hostname: hostname,
                    dns: GCP.DNS("example-zone", zoneName: "example.com", context: context)
                ),
                context: context
            )
            let certificate = try properties(
                type: "gcp:compute:ManagedSslCertificate",
                in: context
            )
            return try #require(certificate["name"] as? String)
        }

        #expect(
            try certificateName(hostname: "api.example.com")
                != certificateName(hostname: "new.example.com")
        )
    }
}

private final class RecordingDNSProvider: DNSProvider, @unchecked Sendable {
    private(set) var recordTypes: [String] = []

    func createRecord(
        type: DNSRecordType,
        name: any Input<String>,
        target: any Input<String>,
        ttl: Duration
    ) -> DNSProviderRecord {
        recordTypes.append(type.description)
        return RecordingDNSRecord(fqdn: "\(name)")
    }

    func createAlias(
        name: any Input<String>,
        target: any Input<String>,
        ttl: Duration
    ) -> DNSProviderRecord {
        recordTypes.append("ALIAS")
        return RecordingDNSRecord(fqdn: "\(name)")
    }
}

private struct RecordingDNSRecord: DNSProviderRecord {
    let fqdn: Output<String>
}
