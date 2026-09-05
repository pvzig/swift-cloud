import Foundation

public final class Store: @unchecked Sendable {
    public typealias Operation = (Context) async throws -> Void

    private let queue = DispatchQueue(label: "com.swift.cloud.store")

    private var _resources: [Resource] = []
    var resources: [Resource] {
        get { queue.sync { _resources } }
        set { queue.sync { _resources = newValue } }
    }

    private var _variables: [any VariableProvider] = []
    var variables: [any VariableProvider] {
        get { queue.sync { _variables } }
        set { queue.sync { _variables = newValue } }
    }

    private var _builds: [Operation] = []
    var builds: [Operation] {
        get { queue.sync { _builds } }
        set { queue.sync { _builds = newValue } }
    }

    private var _environments: [Environment] = []
    var environments: [Environment] {
        get { queue.sync { _environments } }
        set { queue.sync { _environments = newValue } }
    }

    private var _outputs: [String: Output<String>] = [:]
    var outputs: [String: Output<String>] {
        get { queue.sync { _outputs } }
        set { queue.sync { _outputs = newValue } }
    }

    private var _links: [String: LinkProperties] = [:]
    var links: [String: LinkProperties] {
        get { queue.sync { _links } }
        set { queue.sync { _links = newValue } }
    }

    private struct ResourceKey: Hashable {
        let type: String
        let chosenName: String
    }

    private var additionalDependencies: [ResourceKey: [any ResourceProvider]] = [:]
    private var optionOverrides: [ResourceKey: Resource.Options] = [:]
}

extension Store {
    /// Returns the tracked resource with the given provider type and chosen logical name.
    public func resource(type: String, chosenName: String) -> Resource? {
        resources.last {
            $0.type == type && $0.chosenName == chosenName
        }
    }

    public func track(_ resource: Resource) {
        resources.append(resource)
    }

    /// Adds render-time deployment-order dependencies to a tracked resource.
    ///
    /// Keeping the edge in the store means both the originally returned value and
    /// the tracked copy render the same dependency set.
    public func addDependencies(
        _ dependencies: [any ResourceProvider],
        to resource: Resource
    ) {
        guard dependencies.isEmpty == false else {
            return
        }
        queue.sync {
            guard
                _resources.contains(where: {
                    $0.type == resource.type && $0.chosenName == resource.chosenName
                })
            else {
                preconditionFailure("cannot add dependencies to an untracked resource")
            }
            let key = ResourceKey(type: resource.type, chosenName: resource.chosenName)
            additionalDependencies[key, default: []].append(contentsOf: dependencies)
        }
    }

    /// Merges options supplied by a later owner of the same logical resource.
    public func mergeOptions(_ options: Resource.Options?, into resource: Resource) {
        guard let options else {
            return
        }
        queue.sync {
            let key = ResourceKey(type: resource.type, chosenName: resource.chosenName)
            var merged = optionOverrides[key] ?? resource.options ?? .init()
            merged.dependsOn = (merged.dependsOn ?? []) + (options.dependsOn ?? [])
            merged.protect =
                (merged.protect == true || options.protect == true)
                ? true
                : options.protect ?? merged.protect
            if let provider = options.provider {
                if let existingProvider = merged.provider {
                    precondition(
                        existingProvider.output.description == provider.output.description,
                        "one logical resource cannot use two providers"
                    )
                } else {
                    merged.provider = provider
                }
            }
            optionOverrides[key] = merged
        }
    }

    func renderOptions(for resource: Resource) -> Resource.Options? {
        queue.sync {
            let key = ResourceKey(type: resource.type, chosenName: resource.chosenName)
            let options = optionOverrides[key] ?? resource.options
            let dependencies = additionalDependencies[key] ?? []
            guard dependencies.isEmpty == false else {
                return options
            }
            var merged = options ?? .init()
            merged.dependsOn = (merged.dependsOn ?? []) + dependencies
            return merged
        }
    }

    public func track(_ variable: any VariableProvider) {
        variables.append(variable)
    }

    public func track(_ link: any Linkable) {
        if let properties = link.properties {
            links["\(properties.type):\(properties.name)"] = properties
        }
    }

    public func track(_ environment: Environment) {
        environments.append(environment)
    }

    public func setOutput(_ output: String, value: Output<String>) {
        outputs[output] = value
    }

    public func build(_ operation: @escaping Operation) {
        builds.append(operation)
    }
}
