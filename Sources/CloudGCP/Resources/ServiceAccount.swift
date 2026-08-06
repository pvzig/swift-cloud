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
            let accountID = tokenize(context.gcpStage, name, maxLength: 30)
            precondition(
                (6...30).contains(accountID.count),
                "service account IDs must contain between 6 and 30 characters"
            )

            resource = Resource(
                name: "\(name)-service-account",
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
    /// Returns the project-scoped IAM member for `role`, creating it once per identity.
    ///
    /// Google project IAM is a single read-modify-write policy document, so a role
    /// must be owned by exactly one resource. Callers that need the resource itself,
    /// for example to order a dependent resource behind the grant, should use this
    /// rather than declaring their own `gcp:projects:IAMMember`.
    @discardableResult
    public func projectRole(_ role: GCP.IAMRole) -> Resource {
        let roleName = "\(resource.chosenName)-\(tokenize(role.rawValue))-project-role"
        if let existing = resource.context.store.resource(
            type: "gcp:projects:IAMMember",
            chosenName: roleName
        ) {
            return existing
        }

        return Resource(
            name: roleName,
            type: "gcp:projects:IAMMember",
            properties: [
                "project": resource.context.gcpProjectID,
                "role": role.rawValue,
                "member": member,
            ],
            options: resource.options,
            context: resource.context
        )
    }

    /// Grants this identity a project-scoped role.
    @discardableResult
    public func grantProjectRole(_ role: GCP.IAMRole) -> Self {
        _ = projectRole(role)
        return self
    }

    /// Returns the IAM member granting `member` a role on this service account,
    /// creating it once per role and grantee.
    @discardableResult
    public func serviceAccountRole(
        _ role: GCP.IAMRole,
        to member: any Input<String>
    ) -> Resource {
        // The grantee is part of the name because the same role is routinely granted
        // on one service account to several identities; without it the grants share
        // a logical name and all but the last are dropped from the generated project.
        let bindingName = tokenize(
            resource.chosenName,
            tokenize(role.rawValue),
            tokenize("\(member)"),
            "service-account-role"
        )
        if let existing = resource.context.store.resource(
            type: "gcp:serviceaccount:IAMMember",
            chosenName: bindingName
        ) {
            return existing
        }

        return Resource(
            name: bindingName,
            type: "gcp:serviceaccount:IAMMember",
            properties: [
                "serviceAccountId": resource.name,
                "role": role.rawValue,
                "member": member,
            ],
            options: resource.options,
            context: resource.context
        )
    }

    /// Grants `member` a role on this service account.
    @discardableResult
    public func grantServiceAccountRole(
        _ role: GCP.IAMRole,
        to member: any Input<String>
    ) -> Self {
        _ = serviceAccountRole(role, to: member)
        return self
    }
}
