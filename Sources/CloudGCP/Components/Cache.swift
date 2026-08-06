import CloudCore

extension GCP {
    public struct Cache: GCPComponent {
        public let cache: Resource

        public var name: Output<String> {
            cache.name
        }

        public var hostname: Output<String> {
            cache.output.keyPath("host")
        }

        public var port: Output<String> {
            "\(cache.output.keyPath("port") as Output<Int>)"
        }

        public var url: Output<String> {
            "redis://\(hostname):\(port)"
        }

        public init(
            _ name: String,
            vpc: VPC,
            location: Region? = nil,
            tier: Tier = .basic,
            memorySizeGB: Int = 1,
            redisVersion: String = "REDIS_7_2",
            deletionProtection: Bool? = nil,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            precondition(memorySizeGB >= 1, "memorySizeGB must be at least one")

            cache = Resource(
                name: name,
                type: "gcp:redis:Instance",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(context.gcpStage, name),
                    "region": (location ?? context.gcpRegion).rawValue,
                    "tier": tier.rawValue,
                    "memorySizeGb": memorySizeGB,
                    "redisVersion": redisVersion,
                    "authorizedNetwork": vpc.network.id,
                    "connectMode": "PRIVATE_SERVICE_ACCESS",
                    "reservedIpRange": vpc.privateAddress.name,
                    "authEnabled": false,
                    "transitEncryptionMode": "DISABLED",
                    "deletionProtection": deletionProtection ?? context.isProduction,
                ],
                options: options,
                context: context,
                dependsOn: [vpc.privateServiceConnection]
            )
        }
    }
}

extension GCP.Cache {
    public enum Tier: String, Sendable {
        case basic = "BASIC"
        case highAvailability = "STANDARD_HA"
    }
}

extension GCP.Cache: GCPLinkable {
    public var actions: [String] {
        []
    }

    public var resources: [Output<String>] {
        [cache.id]
    }

    public var properties: LinkProperties? {
        .init(
            type: "cache",
            name: cache.chosenName,
            properties: [
                "hostname": hostname,
                "port": port,
                "url": url,
            ]
        )
    }

    public func grantAccess(to serviceAccount: GCP.ServiceAccount) {}
}
