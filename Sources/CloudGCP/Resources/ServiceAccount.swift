import CloudCore

extension GCP {
    public struct ServiceAccount: GCPResourceProvider {
        public let resource: Resource

        public var email: Output<String> {
            resource.output.keyPath("email")
        }

        public var member: Output<String> {
            "serviceAccount:\(email)"
        }

        public init(
            _ name: String,
            displayName: String? = nil,
            description: String? = nil,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            let accountID = tokenize(context.stage, name, maxLength: 30)
            precondition(
                (6...30).contains(accountID.count),
                "service account IDs must contain between 6 and 30 characters"
            )

            resource = Resource(
                name: name,
                type: "gcp:serviceaccount:Account",
                properties: [
                    "project": context.gcpProjectID,
                    "accountId": accountID,
                    "displayName": displayName,
                    "description": description,
                ],
                options: options,
                context: context
            )
        }
    }
}

extension GCP.ServiceAccount {
    /// Grants this identity a project-scoped role.
    @discardableResult
    public func grantProjectRole(_ role: GCP.IAMRole) -> Self {
        _ = Resource(
            name: "\(resource.chosenName)-\(tokenize(role.rawValue))-project-role",
            type: "gcp:projects:IAMMember",
            properties: [
                "project": resource.context.gcpProjectID,
                "role": role.rawValue,
                "member": member,
            ],
            options: resource.options,
            context: resource.context
        )
        return self
    }

    /// Grants `member` a role on this service account.
    @discardableResult
    public func grantServiceAccountRole(
        _ role: GCP.IAMRole,
        to member: any Input<String>
    ) -> Self {
        _ = Resource(
            name: "\(resource.chosenName)-\(tokenize(role.rawValue))-service-account-role",
            type: "gcp:serviceaccount:IAMMember",
            properties: [
                "serviceAccountId": resource.name,
                "role": role.rawValue,
                "member": member,
            ],
            options: resource.options,
            context: resource.context
        )
        return self
    }
}
