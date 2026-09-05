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
        _ = GCP.ProjectService(.cloudRun, context: context)

        let resource = try resource(type: "gcp:projects:Service", in: context)
        #expect(resource.chosenName == "run-googleapis-com-api")

        let api = try properties(type: "gcp:projects:Service", in: context)
        #expect(api["project"] as? String == "example-project")
        #expect(api["service"] as? String == "run.googleapis.com")
        #expect(api["disableOnDestroy"] as? Bool == false)
        #expect(context.store.resources.filter { $0.type == "gcp:projects:Service" }.count == 1)
    }

    @Test("Project services cannot disable a project-wide API on stack destroy")
    func projectServiceDestroyPolicy() async {
        await #expect(processExitsWith: .failure) {
            _ = GCP.ProjectService(
                .storage,
                disableOnDestroy: true,
                context: makeContext()
            )
        }
    }

    @Test("An explicit GCP provider controls project and default region")
    func explicitProvider() throws {
        let context = makeContext()
        let provider = GCP.Provider(
            "secondary",
            projectID: "secondary-project",
            region: .europeWest1,
            context: context
        )
        _ = GCP.Bucket(
            "assets",
            options: .provider(provider),
            context: context
        )
        _ = GCP.Bucket(
            "regional-assets",
            location: .usEast1,
            options: .provider(provider),
            context: context
        )
        let vpc = GCP.VPC(
            "network",
            options: .provider(provider),
            context: context
        )
        _ = GCP.FirewallRule(
            "allow-web",
            vpc: vpc,
            action: .allow([.tcp(["443"])]),
            sourceRanges: ["10.0.0.0/8"],
            options: .provider(provider),
            context: context
        )

        let bucket = try resource(type: "gcp:storage:Bucket", in: context)
        let bucketProperties = try properties(of: bucket)
        #expect(bucketProperties["project"] as? String == "secondary-project")
        #expect(bucketProperties["location"] as? String == "europe-west1")
        #expect((bucketProperties["name"] as? String)?.hasPrefix("secondary-project-") == true)
        let options = try #require(bucket.pulumiProjectResources().values.first?.options)
        #expect(options.provider?.description == "${testing-secondary}")

        let regionalBucket = try properties(
            type: "gcp:storage:Bucket",
            in: context,
            chosenName: "regional-assets"
        )
        #expect(regionalBucket["project"] as? String == "secondary-project")
        #expect(regionalBucket["location"] as? String == "us-east1")

        let subnetwork = try properties(type: "gcp:compute:Subnetwork", in: context)
        #expect(subnetwork["project"] as? String == "secondary-project")
        #expect(subnetwork["region"] as? String == "europe-west1")
        let firewall = try properties(type: "gcp:compute:Firewall", in: context)
        #expect(firewall["project"] as? String == "secondary-project")
    }

    @Test("Reused service identities retain later resource options")
    func sharedServiceIdentityOptions() throws {
        let context = makeContext()
        let api = GCP.ProjectService(.apiGateway, context: context)
        let provider = GCP.Provider(
            "same-project",
            projectID: "example-project",
            context: context
        )
        _ = GCP.ServiceIdentity.shared(.apiGateway, context: context)
        let identity = GCP.ServiceIdentity.shared(
            .apiGateway,
            options: .provider(provider).protect().dependsOn([api]),
            context: context
        )

        let options = try #require(
            identity.resource.pulumiProjectResources().values.first?.options
        )
        #expect(options.protect == true)
        #expect(options.provider?.description == "${testing-same-project}")
        #expect(options.dependsOn?.map(\.description) == ["${testing-apigateway-googleapis-com-api}"])
        #expect(
            context.store.resources.filter {
                $0.type == "gcp:projects:ServiceIdentity"
            }.count == 1
        )
    }

    @Test("Project-scoped resources are distinct across explicit provider projects")
    func sharedResourcesAcrossProjects() {
        let context = makeContext()
        let secondary = GCP.Provider(
            "secondary",
            projectID: "secondary-project",
            context: context
        )

        _ = GCP.ServiceIdentity.shared(.storage, context: context)
        _ = GCP.ServiceIdentity.shared(
            .storage,
            options: .provider(secondary),
            context: context
        )

        let identities = context.store.resources.filter {
            $0.type == "gcp:projects:ServiceIdentity"
        }
        #expect(identities.count == 2)
        #expect(Set(identities.map(\.chosenName)).count == 2)
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
