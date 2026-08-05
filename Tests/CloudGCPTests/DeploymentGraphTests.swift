import Foundation
import Testing

@testable import CloudCore
@testable import CloudGCP

@Suite("GCP deployment graph")
struct DeploymentGraphTests {
    @Test("A production topology encodes without resource-name collisions")
    func productionTopology() throws {
        let context = makeContext(stage: "production")
        let apis: [any ResourceProvider] = [
            GCP.ProjectService(.artifactRegistry, context: context),
            GCP.ProjectService(.cloudDNS, context: context),
            GCP.ProjectService(.cloudRun, context: context),
            GCP.ProjectService(.cloudScheduler, context: context),
            GCP.ProjectService(.cloudSQL, context: context),
            GCP.ProjectService(.compute, context: context),
            GCP.ProjectService(.pubSub, context: context),
            GCP.ProjectService(.redis, context: context),
            GCP.ProjectService(.secretManager, context: context),
            GCP.ProjectService(.serviceNetworking, context: context),
            GCP.ProjectService(.storage, context: context),
        ]
        let options = Resource.Options.dependsOn(apis)
        let identity = GCP.ServiceAccount("backend", options: options, context: context)
        let vpc = GCP.VPC("main", options: options, context: context)
        let repository = GCP.ArtifactRegistry("services", options: options, context: context)
        let image = GCP.ContainerImage(
            "backend",
            targetName: "ExampleService",
            repository: repository,
            context: context
        )
        let bucket = GCP.Bucket("assets", options: options, context: context)
        let secret = GCP.Secret("api-key", options: options, context: context)
        let database = GCP.SQLDatabase(
            "database",
            availability: .regional,
            vpc: vpc,
            readReplicaCount: 1,
            options: options,
            context: context
        )
        let cache = GCP.Cache("cache", vpc: vpc, options: options, context: context)
        let topic = GCP.Topic("events", options: options, context: context)
        let subscription = GCP.Subscription(
            "events-worker",
            topic: topic,
            options: options,
            context: context
        )
        let service = GCP.CloudRunService(
            "backend",
            image: image.reference,
            serviceAccount: identity,
            ingress: .internalLoadBalancer,
            vpc: vpc,
            options: options,
            context: context
        ).link([bucket, secret, database, cache, topic, subscription])
        _ = GCP.SchedulerJob(
            "backend-tick",
            schedule: "*/5 * * * *",
            target: .cloudRun(service, serviceAccount: identity),
            options: options,
            context: context
        )
        let dns = GCP.DNS(
            "example-zone",
            zoneName: "example.com",
            options: options,
            context: context
        )
        _ = GCP.HTTPSLoadBalancer(
            "backend-edge",
            service: service,
            domainName: .init(hostname: "api.example.com", dns: dns),
            cdn: .enabled(),
            options: options,
            context: context
        )

        let resources = context.store.resources.reduce(into: Pulumi.Project.Resources()) {
            $0.merge($1.pulumiProjectResources()) { _, new in new }
        }
        let encoded = try JSONEncoder().encode(resources)
        #expect(encoded.isEmpty == false)
        #expect(resources.count == context.store.resources.count)
        #expect(resources.count >= 45)
        #expect(context.store.builds.count == 1)
    }
}
