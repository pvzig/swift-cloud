import Testing

@testable import CloudCore

@Suite("Project Tests")
struct ProjectTests {
    struct TestProject: Project {
        func build() async throws -> CloudCore.Outputs {
            return [:]
        }
    }

    @Test("Build context")
    func buildContext() async throws {
        let context = Context(
            stage: "testing",
            project: TestProject(),
            package: .init(name: "test"),
            store: .init(),
            builder: .init()
        )
        #expect(context.stage == "testing")
    }

    @Test("Resource options and explicit dependencies are combined")
    func combinedDependencies() throws {
        let context = Context(
            stage: "testing",
            project: TestProject(),
            package: .init(name: "test"),
            store: .init(),
            builder: .init()
        )
        let optionDependency = Resource(
            name: "option-dependency",
            type: "test:Dependency",
            properties: nil,
            options: nil,
            context: context
        )
        let explicitDependency = Resource(
            name: "explicit-dependency",
            type: "test:Dependency",
            properties: nil,
            options: nil,
            context: context
        )
        let resource = Resource(
            name: "subject",
            type: "test:Subject",
            properties: nil,
            options: .dependsOn([optionDependency]),
            context: context,
            dependsOn: [explicitDependency]
        )

        let definition = try #require(resource.pulumiProjectResources().values.first)
        let dependencies = try #require(definition.options?.dependsOn)
        #expect(
            dependencies.map(\.description) == [
                "${testing-option-dependency}",
                "${testing-explicit-dependency}",
            ])
    }
}
