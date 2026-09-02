import CloudCore

/// A resource that can grant a GCP runtime identity access to itself.
///
/// Google IAM is resource- and role-oriented, so GCP links create native IAM
/// members rather than translating through Swift Cloud's AWS inline-policy
/// representation.
public protocol GCPLinkable: Linkable {
    /// Grants `serviceAccount` access without exposing dependency resources.
    ///
    /// Existing custom linkables can continue implementing this method. Native
    /// GCP linkables should implement `accessGrants(to:)` so workload ordering is
    /// explicit.
    func grantAccess(to serviceAccount: GCP.ServiceAccount)

    /// Creates or returns the IAM resources that authorize `serviceAccount`.
    func accessGrants(to serviceAccount: GCP.ServiceAccount) -> [any ResourceProvider]
}

public protocol GCPRoleProvider: EnvironmentProvider {
    var gcpResource: Resource? { get }
    var gcpServiceAccount: GCP.ServiceAccount { get }
    var gcpContext: Context { get }
}

extension GCPLinkable {
    public func accessGrants(to serviceAccount: GCP.ServiceAccount) -> [any ResourceProvider] {
        grantAccess(to: serviceAccount)
        return []
    }
}

extension GCPRoleProvider {
    public var gcpResource: Resource? {
        nil
    }

    @discardableResult
    public func link(_ linkable: any GCPLinkable) -> Self {
        let grants = linkable.accessGrants(to: gcpServiceAccount)
        if let gcpResource {
            gcpContext.store.addDependencies(grants, to: gcpResource)
        }
        environment.merge(linkable.environmentVariables)
        gcpContext.store.track(linkable)
        return self
    }

    @discardableResult
    public func link(_ linkables: [any GCPLinkable]) -> Self {
        for linkable in linkables {
            link(linkable)
        }
        return self
    }

    @discardableResult
    public func link(_ linkables: any GCPLinkable...) -> Self {
        link(linkables)
    }
}

extension GCPLinkable {
    @discardableResult
    public func linkTo(_ provider: any GCPRoleProvider) -> Self {
        provider.link(self)
        return self
    }

    @discardableResult
    public func linkTo(_ providers: any GCPRoleProvider...) -> Self {
        for provider in providers {
            linkTo(provider)
        }
        return self
    }
}
