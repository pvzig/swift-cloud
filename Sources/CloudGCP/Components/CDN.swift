import CloudCore

extension GCP {
    /// A global HTTPS load balancer and Cloud CDN distribution with path-based origins.
    public struct CDN: GCPComponent {
        public let networkEndpointGroups: [Resource]
        public let networkEndpoints: [Resource]
        public let originBackends: [Resource]
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
            origins: [Origin],
            domainName: DomainName,
            policy: HTTPSLoadBalancer.CDN = .enabled(),
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            guard origins.isEmpty == false else {
                preconditionFailure("a CDN requires at least one origin")
            }
            guard let defaultOriginIndex = origins.firstIndex(where: \.isDefault) else {
                preconditionFailure("a CDN requires one origin with path '*' or '/*'")
            }
            precondition(
                origins.filter(\.isDefault).count == 1,
                "a CDN requires exactly one default origin"
            )
            for origin in origins {
                origin.validate()
            }

            self.domainName = domainName
            var endpointGroups: [Resource] = []
            var endpoints: [Resource] = []
            var backends: [Resource] = []

            for (offset, origin) in origins.enumerated() {
                let originName = "\(name)-origin-\(offset + 1)"

                switch origin.source {
                case .bucket(let bucket):
                    let backend = Resource(
                        name: "\(originName)-backend",
                        type: "gcp:compute:BackendBucket",
                        properties: [
                            "project": context.gcpProjectID,
                            "name": tokenize(
                                context.gcpStage,
                                name,
                                "origin",
                                "\(offset + 1)",
                                "backend",
                                maxLength: 63
                            ),
                            "bucketName": bucket.name,
                            "enableCdn": policy.isEnabled,
                            "cdnPolicy": policy.properties,
                            "compressionMode": "AUTOMATIC",
                        ],
                        options: options,
                        context: context
                    )
                    backends.append(backend)

                case .cloudRun(let service):
                    precondition(
                        service.ingress == .internalLoadBalancer,
                        "CDN-backed Cloud Run services require internalLoadBalancer ingress"
                    )
                    service.makePublic()
                    let endpointGroup = Resource(
                        name: "\(originName)-neg",
                        type: "gcp:compute:RegionNetworkEndpointGroup",
                        properties: [
                            "project": context.gcpProjectID,
                            "name": tokenize(
                                context.gcpStage,
                                name,
                                "origin",
                                "\(offset + 1)",
                                "neg",
                                maxLength: 63
                            ),
                            // A serverless NEG must live in the same region as its
                            // Cloud Run service, which may differ per origin.
                            "region": service.location,
                            "networkEndpointType": "SERVERLESS",
                            "cloudRun": ["service": service.name],
                        ],
                        options: options,
                        context: context
                    )
                    endpointGroups.append(endpointGroup)
                    let backend = Resource(
                        name: "\(originName)-backend",
                        type: "gcp:compute:BackendService",
                        properties: [
                            "project": context.gcpProjectID,
                            "name": tokenize(
                                context.gcpStage,
                                name,
                                "origin",
                                "\(offset + 1)",
                                "backend",
                                maxLength: 63
                            ),
                            "loadBalancingScheme": "EXTERNAL_MANAGED",
                            "protocol": "HTTP",
                            "enableCdn": policy.isEnabled,
                            "cdnPolicy": policy.properties,
                            "backends": [["group": endpointGroup.id]],
                            "logConfig": ["enable": true, "sampleRate": 1.0],
                        ],
                        options: options,
                        context: context
                    )
                    backends.append(backend)

                case .external(let hostname, let port, let originProtocol):
                    let endpointGroup = Resource(
                        name: "\(originName)-neg",
                        type: "gcp:compute:GlobalNetworkEndpointGroup",
                        properties: [
                            "project": context.gcpProjectID,
                            "name": tokenize(
                                context.gcpStage,
                                name,
                                "origin",
                                "\(offset + 1)",
                                "neg",
                                maxLength: 63
                            ),
                            "networkEndpointType": "INTERNET_FQDN_PORT",
                            "defaultPort": port,
                        ],
                        options: options,
                        context: context
                    )
                    endpointGroups.append(endpointGroup)
                    let endpoint = Resource(
                        name: "\(originName)-endpoint",
                        type: "gcp:compute:GlobalNetworkEndpoint",
                        properties: [
                            "project": context.gcpProjectID,
                            "globalNetworkEndpointGroup": endpointGroup.name,
                            "fqdn": hostname,
                            "port": port,
                        ],
                        options: options,
                        context: context
                    )
                    endpoints.append(endpoint)
                    let backend = Resource(
                        name: "\(originName)-backend",
                        type: "gcp:compute:BackendService",
                        properties: [
                            "project": context.gcpProjectID,
                            "name": tokenize(
                                context.gcpStage,
                                name,
                                "origin",
                                "\(offset + 1)",
                                "backend",
                                maxLength: 63
                            ),
                            "loadBalancingScheme": "EXTERNAL_MANAGED",
                            "protocol": originProtocol.rawValue,
                            "enableCdn": policy.isEnabled,
                            "cdnPolicy": policy.properties,
                            "backends": [["group": endpointGroup.id]],
                            "customRequestHeaders": ["Host: \(hostname)"],
                            "logConfig": ["enable": true, "sampleRate": 1.0],
                        ],
                        options: options,
                        context: context,
                        dependsOn: [endpoint]
                    )
                    backends.append(backend)
                }
            }

            networkEndpointGroups = endpointGroups
            networkEndpoints = endpoints
            originBackends = backends
            let defaultBackend = backends[defaultOriginIndex]
            let pathRules = origins.enumerated().compactMap { offset, origin -> AnyEncodable? in
                guard origin.isDefault == false else {
                    return nil
                }
                return [
                    "paths": [origin.urlMapPath],
                    "service": backends[offset].id,
                ]
            }

            urlMap = Resource(
                name: "\(name)-url-map",
                type: "gcp:compute:URLMap",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(context.gcpStage, name, "url-map", maxLength: 63),
                    "defaultService": defaultBackend.id,
                    "hostRules": [["hosts": [domainName.hostname], "pathMatcher": "origins"]],
                    "pathMatchers": [
                        [
                            "name": "origins",
                            "defaultService": defaultBackend.id,
                            "pathRules": pathRules,
                        ]
                    ],
                ],
                options: options,
                context: context
            )

            certificate = Resource(
                name: "\(name)-certificate",
                type: "gcp:compute:ManagedSslCertificate",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(
                        context.gcpStage,
                        name,
                        "certificate",
                        digest(domainName.hostname),
                        maxLength: 63
                    ),
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
                    "name": tokenize(context.gcpStage, name, "https-proxy", maxLength: 63),
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
                    "name": tokenize(context.gcpStage, name, "address", maxLength: 63),
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
                    "name": tokenize(context.gcpStage, name, maxLength: 63),
                    "target": proxy.id,
                    "ipAddress": address.output.keyPath("address"),
                    "ipProtocol": "TCP",
                    "portRange": "443",
                    "loadBalancingScheme": "EXTERNAL_MANAGED",
                ],
                options: options,
                context: context
            )

            dnsRecord = domainName.dns.createRecord(
                type: .a,
                name: domainName.hostname,
                target: address.output.keyPath("address"),
                ttl: .seconds(300)
            )
        }
    }
}

extension GCP.CDN {
    public struct Origin: Sendable {
        public let path: String
        public let source: Source

        public static func bucket(_ bucket: GCP.Bucket, path: String) -> Self {
            .init(path: path, source: .bucket(bucket))
        }

        public static func cloudRun(_ service: GCP.CloudRunService, path: String) -> Self {
            .init(path: path, source: .cloudRun(service))
        }

        public static func external(
            hostname: String,
            port: Int = 443,
            protocol originProtocol: OriginProtocol = .https,
            path: String
        ) -> Self {
            .init(
                path: path,
                source: .external(hostname: hostname, port: port, protocol: originProtocol)
            )
        }

        fileprivate var isDefault: Bool {
            path == "*" || path == "/*"
        }

        fileprivate var urlMapPath: String {
            guard isDefault == false, path.hasSuffix("/*") == false else {
                return path
            }
            return "\(path.hasSuffix("/") ? String(path.dropLast()) : path)/*"
        }

        fileprivate func validate() {
            precondition(path.isEmpty == false, "CDN origin paths must not be empty")
            precondition(isDefault || path.hasPrefix("/"), "CDN origin paths must begin with '/'")
            if case .external(let hostname, let port, _) = source {
                precondition(hostname.isEmpty == false, "external origin hostnames must not be empty")
                precondition(hostname.contains("://") == false, "external origin hostnames must not include a scheme")
                precondition((1...65_535).contains(port), "external origin ports must be valid TCP ports")
            }
        }
    }

    public enum Source: Sendable {
        case bucket(GCP.Bucket)
        case cloudRun(GCP.CloudRunService)
        case external(hostname: String, port: Int, protocol: OriginProtocol)
    }

    public enum OriginProtocol: String, Sendable {
        case http = "HTTP"
        case https = "HTTPS"
    }
}

extension [GCP.CDN.Origin] {
    public static func bucket(_ bucket: GCP.Bucket) -> Self {
        [.bucket(bucket, path: "*")]
    }

    public static func cloudRun(_ service: GCP.CloudRunService) -> Self {
        [.cloudRun(service, path: "*")]
    }

    public static func external(
        hostname: String,
        port: Int = 443,
        protocol originProtocol: GCP.CDN.OriginProtocol = .https
    ) -> Self {
        [.external(hostname: hostname, port: port, protocol: originProtocol, path: "*")]
    }
}
