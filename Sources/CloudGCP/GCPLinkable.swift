import CloudCore

/// A resource that can grant a GCP runtime identity access to itself.
///
/// Google IAM is resource- and role-oriented, so GCP links create native IAM
/// members rather than translating through Swift Cloud's AWS inline-policy
/// representation.
public protocol GCPLinkable: Linkable {
    func grantAccess(to serviceAccount: GCP.ServiceAccount)
}

public protocol GCPRoleProvider: EnvironmentProvider {
    var gcpServiceAccount: GCP.ServiceAccount { get }
    var gcpContext: Context { get }
}

extension GCPRoleProvider {
    @discardableResult
    public func link(_ linkable: any GCPLinkable) -> Self {
        linkable.grantAccess(to: gcpServiceAccount)
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
