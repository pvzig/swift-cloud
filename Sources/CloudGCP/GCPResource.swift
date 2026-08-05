import CloudCore

public protocol GCPResourceProvider: ResourceProvider {}

extension Resource: GCPResourceProvider {}
