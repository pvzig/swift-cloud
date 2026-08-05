import Testing

@testable import CloudCore
@testable import CloudGCP

@Suite("GCP provider")
struct GCPProviderTests {
    @Test("GCPProject configures the current project and provider plugins")
    func projectConfiguration() throws {
        let project = TestGCPProject()
        let provider = try #require(project.providers.first)

        #expect(provider.name == "gcp")
        #expect(provider.plugin.version == "9.33.0")
        #expect(provider.configuration["project"] == "example-project")
        #expect(provider.configuration["region"] == "us-east1")
        #expect(provider.dependencies.map(\.name) == ["docker-build"])
        #expect(provider.dependencies.map(\.version) == ["0.0.22"])
    }

    @Test("Project service owns explicit API activation")
    func projectService() throws {
        let context = makeContext()
        _ = GCP.ProjectService(.cloudRun, context: context)

        let resource = try resource(type: "gcp:projects:Service", in: context)
        #expect(resource.chosenName == "run-googleapis-com-api")

        let api = try properties(type: "gcp:projects:Service", in: context)
        #expect(api["project"] as? String == "example-project")
        #expect(api["service"] as? String == "run.googleapis.com")
        #expect(api["disableOnDestroy"] as? Bool == false)
    }
}
