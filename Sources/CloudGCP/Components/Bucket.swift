import CloudCore

extension GCP {
    public struct Bucket: GCPComponent {
        public let bucket: Resource

        public var name: Output<String> {
            bucket.name
        }

        public var url: Output<String> {
            bucket.output.keyPath("url")
        }

        public init(
            _ name: String,
            location: Region? = nil,
            storageClass: StorageClass = .standard,
            versioningEnabled: Bool = false,
            publicReadAccess: Bool = false,
            forceDestroy: Bool = false,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            bucket = Resource(
                name: name,
                type: "gcp:storage:Bucket",
                properties: [
                    "project": context.gcpProjectID,
                    "name": tokenize(
                        context.gcpProjectID,
                        context.stage,
                        name,
                        maxLength: 63
                    ),
                    "location": (location ?? context.gcpRegion).rawValue,
                    "storageClass": storageClass.rawValue,
                    "uniformBucketLevelAccess": true,
                    "publicAccessPrevention": publicReadAccess ? "inherited" : "enforced",
                    "versioning": ["enabled": versioningEnabled],
                    "forceDestroy": forceDestroy,
                ],
                options: options,
                context: context
            )

            if publicReadAccess {
                _ = Resource(
                    name: "\(name)-public-object-viewer",
                    type: "gcp:storage:BucketIAMMember",
                    properties: [
                        "bucket": bucket.name,
                        "role": GCP.IAMRole.storageObjectViewer.rawValue,
                        "member": "allUsers",
                    ],
                    options: options,
                    context: context
                )
            }
        }
    }
}

extension GCP.Bucket {
    public enum StorageClass: String, Sendable {
        case standard = "STANDARD"
        case nearline = "NEARLINE"
        case coldline = "COLDLINE"
        case archive = "ARCHIVE"
    }

    @discardableResult
    public func allowObjectAccess(from serviceAccount: GCP.ServiceAccount) -> Self {
        _ = Resource(
            name: "\(bucket.chosenName)-object-user-\(serviceAccount.resource.chosenName)",
            type: "gcp:storage:BucketIAMMember",
            properties: [
                "bucket": name,
                "role": GCP.IAMRole.storageObjectUser.rawValue,
                "member": serviceAccount.member,
            ],
            options: bucket.options,
            context: bucket.context
        )
        return self
    }
}

extension GCP.Bucket: GCPLinkable {
    public var actions: [String] {
        [GCP.IAMRole.storageObjectUser.rawValue]
    }

    public var resources: [Output<String>] {
        [bucket.id]
    }

    public var properties: LinkProperties? {
        .init(
            type: "bucket",
            name: bucket.chosenName,
            properties: [
                "name": name,
                "url": url,
            ]
        )
    }

    public func grantAccess(to serviceAccount: GCP.ServiceAccount) {
        allowObjectAccess(from: serviceAccount)
    }
}
