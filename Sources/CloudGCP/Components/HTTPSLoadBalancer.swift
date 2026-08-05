import CloudCore

extension GCP {
    /// A global HTTPS load balancer for one Cloud Run service.
    ///
    /// Use Cloud Run's `internalLoadBalancer` ingress mode to prevent direct
    /// public access through the service's `run.app` hostname. Google-managed
    /// certificates become active after the generated DNS record resolves.
    public struct HTTPSLoadBalancer: GCPComponent {
        public let networkEndpointGroup: Resource
        public let backendService: Resource
        public let urlMap: Resource
        public let certificate: Resource
        public let proxy: Resource
        public let address: Resource
        public let forwardingRule: Resource
        public let dnsRecord: any DNSProviderRecord
        public let domainName: DomainName

        public var name: Output<String> {
            forwardingRule.name
        }

        public var hostname: Output<String> {
            "\(domainName.hostname)"
        }

        public var url: Output<String> {
            "https://\(hostname)"
        }

        public var ipAddress: Output<String> {
            address.output.keyPath("address")
        }

        public init(
            _ name: String,
            service: CloudRunService,
            domainName: DomainName,
            cdn: CDN = .disabled,
            location: Region? = nil,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            self.domainName = domainName
            service.makePublic()
            let resourceName = tokenize(context.stage, name)

            networkEndpointGroup = Resource(
                name: "\(name)-neg",
                type: "gcp:compute:RegionNetworkEndpointGroup",
                properties: [
                    "project": context.gcpProjectID,
                    "name": "\(resourceName)-neg",
                    "region": (location ?? context.gcpRegion).rawValue,
                    "networkEndpointType": "SERVERLESS",
                    "cloudRun": ["service": service.name],
                ],
                options: options,
                context: context
            )

            backendService = Resource(
                name: "\(name)-backend",
                type: "gcp:compute:BackendService",
                properties: [
                    "project": context.gcpProjectID,
                    "name": "\(resourceName)-backend",
                    "loadBalancingScheme": "EXTERNAL_MANAGED",
                    "protocol": "HTTP",
                    "timeoutSec": 30,
                    "enableCdn": cdn.isEnabled,
                    "cdnPolicy": cdn.properties,
                    "backends": [["group": networkEndpointGroup.id]],
                    "logConfig": ["enable": true, "sampleRate": 1.0],
                ],
                options: options,
                context: context
            )

            urlMap = Resource(
                name: "\(name)-url-map",
                type: "gcp:compute:URLMap",
                properties: [
                    "project": context.gcpProjectID,
                    "name": "\(resourceName)-url-map",
                    "defaultService": backendService.id,
                ],
                options: options,
                context: context
            )

            certificate = Resource(
                name: "\(name)-certificate",
                type: "gcp:compute:ManagedSslCertificate",
                properties: [
                    "project": context.gcpProjectID,
                    "name": "\(resourceName)-certificate",
                    "managed": ["domains": [domainName.hostname]],
                ],
                options: options,
                context: context
            )

            proxy = Resource(
                name: "\(name)-https-proxy",
                type: "gcp:compute:TargetHttpsProxy",
                properties: [
                    "project": context.gcpProjectID,
                    "name": "\(resourceName)-https-proxy",
                    "urlMap": urlMap.id,
                    "sslCertificates": [certificate.id],
                    "quicOverride": "ENABLE",
                ],
                options: options,
                context: context
            )

            address = Resource(
                name: "\(name)-address",
                type: "gcp:compute:GlobalAddress",
                properties: [
                    "project": context.gcpProjectID,
                    "name": "\(resourceName)-address",
                    "addressType": "EXTERNAL",
                    "ipVersion": "IPV4",
                ],
                options: options,
                context: context
            )

            forwardingRule = Resource(
                name: name,
                type: "gcp:compute:GlobalForwardingRule",
                properties: [
                    "project": context.gcpProjectID,
                    "name": resourceName,
                    "target": proxy.id,
                    "ipAddress": address.output.keyPath("address"),
                    "ipProtocol": "TCP",
                    "portRange": "443",
                    "loadBalancingScheme": "EXTERNAL_MANAGED",
                ],
                options: options,
                context: context
            )

            dnsRecord = domainName.dns.createAlias(
                name: domainName.hostname,
                target: address.output.keyPath("address"),
                ttl: .seconds(300)
            )
        }
    }
}

extension GCP.HTTPSLoadBalancer {
    public enum CDN: Sendable {
        case disabled
        case enabled(defaultTTL: Duration = .seconds(3600), maximumTTL: Duration = .seconds(86_400))

        fileprivate var isEnabled: Bool {
            switch self {
            case .disabled: false
            case .enabled: true
            }
        }

        fileprivate var properties: AnyEncodable? {
            switch self {
            case .disabled:
                nil
            case .enabled(let defaultTTL, let maximumTTL):
                [
                    "cacheMode": "CACHE_ALL_STATIC",
                    "defaultTtl": defaultTTL.components.seconds,
                    "maxTtl": maximumTTL.components.seconds,
                    "negativeCaching": true,
                    "serveWhileStale": 86_400,
                ]
            }
        }
    }
}
