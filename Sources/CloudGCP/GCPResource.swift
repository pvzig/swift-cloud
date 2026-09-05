import CloudCore

public protocol GCPResourceProvider: ResourceProvider {}

extension Resource: GCPResourceProvider {}

extension Resource {
    var gcpProjectID: String {
        (options?.provider as? GCP.Provider)?.projectID ?? context.gcpProjectID
    }
}

extension GCP {
    static func resolvedRegion(
        _ explicitRegion: Region?,
        options: Resource.Options?,
        context: Context
    ) -> Region {
        explicitRegion
            ?? (options?.provider as? GCP.Provider)?.region
            ?? context.gcpRegion
    }

    /// Returns a previously declared logical resource or creates its single owner.
    static func sharedResource(
        name: String,
        type: String,
        properties: AnyEncodable?,
        options: Resource.Options?,
        context: Context,
        dependsOn: [any ResourceProvider]? = nil
    ) -> Resource {
        let scopedName: String
        if let provider = options?.provider as? GCP.Provider,
            provider.projectID != context.gcpProjectID
        {
            scopedName = "\(name)-\(digest(provider.projectID))"
        } else {
            scopedName = name
        }
        if let existing = context.store.resource(type: type, chosenName: scopedName) {
            context.store.mergeOptions(options, into: existing)
            context.store.addDependencies(dependsOn ?? [], to: existing)
            return existing
        }
        return Resource(
            name: scopedName,
            type: type,
            properties: properties,
            options: options,
            context: context,
            dependsOn: dependsOn
        )
    }
}
