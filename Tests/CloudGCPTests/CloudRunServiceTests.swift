import Testing

@testable import CloudCore
@testable import CloudGCP

@Suite("GCP Cloud Run")
struct CloudRunServiceTests {
    @Test("Cloud Run emits h2c, sidecar, secret, and Cloud SQL configuration")
    func serviceShape() throws {
        let context = makeContext()
        let serviceAccount = GCP.ServiceAccount("backend", context: context)
        let collector = GCP.CloudRunService.Sidecar(
            "collector",
            image: "us-docker.pkg.dev/example/collector:latest",
            cpuAllocation: .always,
            arguments: ["--config=/etc/otel/config.yaml"],
            volumeMounts: [.init("otel-config", path: "/etc/otel")],
            startupProbe: .http(path: "/", port: 13_133),
            livenessProbe: .http(path: "/", port: 13_133)
        )
        let service = GCP.CloudRunService(
            "backend",
            image: "us-docker.pkg.dev/example/backend@sha256:abc",
            serviceAccount: serviceAccount,
            protocol: .http2,
            cpuAllocation: .always,
            requestConcurrency: 40,
            scaling: .init(minimumInstances: 1, maximumInstances: 4),
            environment: ["service-name": "backend"],
            secretEnvironment: [.init("db-password", secret: "db-password", version: "2")],
            applicationDependencies: ["collector"],
            applicationVolumeMounts: [.init("cloudsql", path: "/cloudsql")],
            sidecars: [collector],
            volumes: [
                .cloudSQL(name: "cloudsql", instances: ["example-project:us-east1:main"]),
                .secret(
                    name: "otel-config",
                    secret: "otel-config",
                    items: [.init(version: "1", path: "config.yaml")]
                ),
            ],
            publicAccess: true,
            context: context
        )

        #expect(service.url.description == "${testing-backend.uri}")

        let serviceProperties = try properties(type: "gcp:cloudrunv2:Service", in: context)
        #expect(serviceProperties["project"] as? String == "example-project")
        #expect(serviceProperties["name"] as? String == "testing-backend")
        #expect(serviceProperties["location"] as? String == "us-east1")

        let scaling = try #require(serviceProperties["scaling"] as? [String: Any])
        #expect(scaling["minInstanceCount"] as? Int == 1)
        #expect(scaling["maxInstanceCount"] as? Int == 4)

        let template = try #require(serviceProperties["template"] as? [String: Any])
        #expect(template["serviceAccount"] as? String == "${testing-backend-service-account.email}")
        #expect(template["maxInstanceRequestConcurrency"] as? Int == 40)

        let containers = try #require(template["containers"] as? [[String: Any]])
        #expect(containers.count == 2)
        let application = try #require(containers.first)
        let port = try #require(application["ports"] as? [String: Any])
        #expect(port["name"] as? String == "h2c")
        #expect(port["containerPort"] as? Int == 8080)
        #expect(application["dependsOns"] as? [String] == ["collector"])

        let resources = try #require(application["resources"] as? [String: Any])
        #expect(resources["cpuIdle"] as? Bool == false)

        let environment = try #require(application["envs"] as? [[String: Any]])
        // Cloud Run reserves PORT and rejects deployments that set it explicitly.
        #expect(environment.contains { $0["name"] as? String == "PORT" } == false)
        #expect(environment.contains { $0["name"] as? String == "SERVICE_NAME" })
        #expect(environment.contains { $0["name"] as? String == "DB_PASSWORD" && $0["valueSource"] != nil })

        let volumes = try #require(template["volumes"] as? [[String: Any]])
        #expect(volumes.count == 2)
        #expect(containers[1]["startupProbe"] != nil)
        #expect(containers[1]["livenessProbe"] != nil)

        let publicBinding = try properties(
            type: "gcp:cloudrunv2:ServiceIamMember",
            in: context,
            chosenName: "backend-invoker-public"
        )
        #expect(publicBinding["member"] as? String == "allUsers")
        #expect(publicBinding["role"] as? String == "roles/run.invoker")
    }

    @Test("A secret environment variable wins over a literal that normalizes to the same name")
    func environmentNameCollision() throws {
        let context = makeContext()
        _ = GCP.CloudRunService(
            "backend",
            image: "us-docker.pkg.dev/example/backend:latest",
            environment: ["api-key": "literal", "region": "us-east1"],
            secretEnvironment: [.init("API_KEY", secret: "api-key")],
            context: context
        )

        let serviceProperties = try properties(type: "gcp:cloudrunv2:Service", in: context)
        let template = try #require(serviceProperties["template"] as? [String: Any])
        let containers = try #require(template["containers"] as? [[String: Any]])
        let environment = try #require(containers.first?["envs"] as? [[String: Any]])

        // Cloud Run rejects duplicate env names outright.
        let apiKeys = environment.filter { $0["name"] as? String == "API_KEY" }
        #expect(apiKeys.count == 1)
        #expect(apiKeys.first?["valueSource"] != nil)
        #expect(apiKeys.first?["value"] == nil)
        #expect(environment.contains { $0["name"] as? String == "REGION" })
    }

    @Test("Container image uses Artifact Registry and an immutable output reference")
    func containerImage() throws {
        let context = makeContext()
        let repository = GCP.ArtifactRegistry("containers", context: context)
        let image = GCP.ContainerImage(
            "backend",
            targetName: "ExampleService",
            repository: repository,
            context: context
        )

        #expect(image.reference.description == "${testing-backend-image.ref}")

        let imageResource = try resource(type: "docker-build:Image", in: context)
        #expect(imageResource.dependsOn?.count == 1)
        let imageProperties = try properties(type: "docker-build:Image", in: context)
        #expect(imageProperties["push"] as? Bool == true)
        #expect(imageProperties["platforms"] as? [String] == ["linux/amd64"])
        #expect(context.store.builds.count == 1)
    }
}
