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
        #expect(project.home is GCP.Home)
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

    @Test("Stages that do not start with a letter still produce valid GCP names")
    func numericStageNaming() throws {
        // Stages default to the current git branch, which is frequently a ticket
        // number. Google Cloud requires names to match [a-z]([-a-z0-9]*[a-z0-9])?.
        let context = makeContext(stage: "123-fix-login")
        #expect(context.stage == "123-fix-login")
        #expect(context.gcpStage == "s-123-fix-login")

        _ = GCP.ServiceAccount("backend", context: context)
        _ = GCP.CloudRunService(
            "backend",
            image: "us-docker.pkg.dev/example/backend:latest",
            context: context
        )
        _ = GCP.Bucket("assets", context: context)

        let account = try properties(type: "gcp:serviceaccount:Account", in: context)
        let service = try properties(type: "gcp:cloudrunv2:Service", in: context)
        let bucket = try properties(type: "gcp:storage:Bucket", in: context)
        for name in [
            account["accountId"] as? String,
            service["name"] as? String,
            bucket["name"] as? String,
        ] {
            let name = try #require(name)
            #expect(name.first?.isLetter == true, "\(name) must begin with a letter")
        }
    }

    @Test("Letter-led stages are left untouched")
    func letterStageNaming() {
        #expect(makeContext(stage: "production").gcpStage == "production")
    }
}
