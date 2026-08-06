import CloudCore

extension GCP {
    /// Secret Manager metadata and IAM access.
    ///
    /// Secret payload versions are intentionally managed outside Swift Cloud
    /// until the framework can represent encrypted inputs without writing
    /// plaintext into generated Pulumi YAML.
    public struct Secret: GCPComponent {
        public let secret: Resource

        public var name: Output<String> {
            secret.name
        }

        public var secretID: Output<String> {
            secret.output.keyPath("secretId")
        }

        public init(
            _ name: String,
            deletionProtection: Bool? = nil,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            secret = Resource(
                name: name,
                type: "gcp:secretmanager:Secret",
                properties: [
                    "project": context.gcpProjectID,
                    "secretId": tokenize(context.gcpStage, name),
                    "replication": ["auto": [:] as [String: String]],
                    "deletionProtection": deletionProtection ?? context.isProduction,
                ],
                options: options,
                context: context
            )
        }
    }
}

extension GCP.Secret {
    @discardableResult
    public func allowAccess(from serviceAccount: GCP.ServiceAccount) -> Self {
        _ = Resource(
            name: "\(secret.chosenName)-accessor-\(serviceAccount.resource.chosenName)",
            type: "gcp:secretmanager:SecretIamMember",
            properties: [
                "project": secret.context.gcpProjectID,
                "secretId": secretID,
                "role": GCP.IAMRole.secretAccessor.rawValue,
                "member": serviceAccount.member,
            ],
            options: secret.options,
            context: secret.context
        )
        return self
    }
}

extension GCP.Secret: GCPLinkable {
    public var actions: [String] {
        [GCP.IAMRole.secretAccessor.rawValue]
    }

    public var resources: [Output<String>] {
        [secret.id]
    }

    public var properties: LinkProperties? {
        .init(
            type: "secret",
            name: secret.chosenName,
            properties: ["name": secretID]
        )
    }

    public func grantAccess(to serviceAccount: GCP.ServiceAccount) {
        allowAccess(from: serviceAccount)
    }
}
