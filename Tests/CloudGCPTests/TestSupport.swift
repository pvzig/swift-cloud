import Foundation
import Testing

@testable import CloudCore
@testable import CloudGCP

struct TestGCPProject: GCPProject {
    let projectID = "example-project"
    let region = GCP.Region.usEast1

    func build() async throws -> Outputs {
        [:]
    }
}

func makeContext(stage: String = "testing") -> Context {
    Context(
        stage: stage,
        project: TestGCPProject(),
        package: .init(name: "test"),
        store: .init(),
        builder: .init()
    )
}

func resource(
    type: String,
    in context: Context,
    chosenName: String? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> Resource {
    try #require(
        context.store.resources.first {
            $0.type == type && (chosenName == nil || $0.chosenName == chosenName)
        },
        sourceLocation: sourceLocation
    )
}

func properties(
    type: String,
    in context: Context,
    chosenName: String? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> [String: Any] {
    let resource = try resource(
        type: type,
        in: context,
        chosenName: chosenName,
        sourceLocation: sourceLocation
    )
    let encoded = try JSONEncoder().encode(
        try #require(resource.properties, sourceLocation: sourceLocation)
    )
    return try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any],
        sourceLocation: sourceLocation
    )
}

func variableDefinitions(
    in context: Context,
    sourceLocation: SourceLocation = #_sourceLocation
) throws -> [String: Any] {
    let definitions = context.store.variables.reduce(into: Pulumi.Project.Variables()) {
        $0.merge($1.pulumiProjectVariables()) { _, new in new }
    }
    let encoded = try JSONEncoder().encode(definitions)
    return try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any],
        sourceLocation: sourceLocation
    )
}
