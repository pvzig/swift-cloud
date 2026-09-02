import Testing

@testable import CloudCore
@testable import CloudGCP

@Suite("GCP Cloud Run workloads")
struct CloudRunWorkloadTests {
    @Test("Cloud Run jobs support execution, scheduling, secrets, VPC access, and links")
    func job() throws {
        let context = makeContext()
        let identity = GCP.ServiceAccount("job-runner", context: context)
        let schedulerIdentity = GCP.ServiceAccount("job-scheduler", context: context)
        let vpc = GCP.VPC("main", context: context)
        let bucket = GCP.Bucket("results", context: context)
        let job = GCP.CloudRunJob(
            "processor",
            image: "us-docker.pkg.dev/example/processor:latest",
            serviceAccount: identity,
            taskCount: 8,
            parallelism: 4,
            timeout: .seconds(900) + .milliseconds(500),
            environment: ["mode": "batch"],
            secretEnvironment: [.init("api-key", secret: "api-key")],
            command: ["./processor"],
            arguments: ["--once"],
            vpc: vpc,
            context: context
        ).link(bucket)
        _ = GCP.SchedulerJob(
            "processor-nightly",
            schedule: "0 2 * * *",
            target: .cloudRunJob(job, serviceAccount: schedulerIdentity),
            context: context
        )

        let jobProperties = try properties(type: "gcp:cloudrunv2:Job", in: context)
        let execution = try #require(jobProperties["template"] as? [String: Any])
        #expect(execution["taskCount"] as? Int == 8)
        #expect(execution["parallelism"] as? Int == 4)
        let template = try #require(execution["template"] as? [String: Any])
        #expect(template["serviceAccount"] as? String == "${testing-job-runner-service-account.email}")
        #expect(template["timeout"] as? String == "900.5s")
        let containers = try #require(template["containers"] as? [[String: Any]])
        let container = try #require(containers.first)
        #expect(container["commands"] as? [String] == ["./processor"])
        #expect(container["args"] as? [String] == ["--once"])
        let environment = try #require(container["envs"] as? [[String: Any]])
        #expect(environment.contains { $0["name"] as? String == "MODE" })
        #expect(environment.contains { $0["name"] as? String == "API_KEY" && $0["valueSource"] != nil })

        let scheduler = try properties(type: "gcp:cloudscheduler:Job", in: context)
        let target = try #require(scheduler["httpTarget"] as? [String: Any])
        #expect(
            target["uri"] as? String
                == "https://run.googleapis.com/v2/projects/example-project/locations/${testing-processor.location}/jobs/${testing-processor.name}:run"
        )
        let token = try #require(target["oauthToken"] as? [String: Any])
        #expect(token["serviceAccountEmail"] as? String == "${testing-job-scheduler-service-account.email}")
        #expect(context.store.resources.contains { $0.type == "gcp:cloudrunv2:JobIamMember" })
        #expect(context.store.resources.contains { $0.type == "gcp:storage:BucketIAMMember" })
        #expect(job.environment.values.keys.contains("BUCKET_RESULTS_NAME"))
    }

    @Test("Cloud Run worker pools support automatic scaling and linked resources")
    func workerPool() throws {
        let context = makeContext()
        let identity = GCP.ServiceAccount("worker-identity", context: context)
        let bucket = GCP.Bucket("work-items", context: context)
        let worker = GCP.CloudRunWorkerPool(
            "consumer",
            image: "us-docker.pkg.dev/example/consumer:latest",
            serviceAccount: identity,
            scaling: .automatic(minimumInstances: 1, maximumInstances: 10),
            environment: ["subscription": "jobs"],
            context: context
        ).link(bucket)

        let properties = try properties(type: "gcp:cloudrunv2:WorkerPool", in: context)
        let scaling = try #require(properties["scaling"] as? [String: Any])
        #expect(scaling["scalingMode"] as? String == "AUTOMATIC")
        #expect(scaling["minInstanceCount"] as? Int == 1)
        #expect(scaling["maxInstanceCount"] as? Int == 10)
        let template = try #require(properties["template"] as? [String: Any])
        #expect(template["serviceAccount"] as? String == "${testing-worker-identity-service-account.email}")
        #expect(worker.environment.values.keys.contains("BUCKET_WORK_ITEMS_NAME"))
    }

    @Test("Cloud Run jobs reject duplicate normalized secret names")
    func duplicateJobSecretEnvironmentNames() async {
        await #expect(processExitsWith: .failure) {
            _ = GCP.CloudRunJob(
                "processor",
                image: "us-docker.pkg.dev/example/processor:latest",
                secretEnvironment: [
                    .init("api-key", secret: "first"),
                    .init("API_KEY", secret: "second"),
                ],
                context: makeContext()
            )
        }
    }

    @Test("Cloud Run worker pools reject duplicate normalized secret names")
    func duplicateWorkerPoolSecretEnvironmentNames() async {
        await #expect(processExitsWith: .failure) {
            _ = GCP.CloudRunWorkerPool(
                "consumer",
                image: "us-docker.pkg.dev/example/consumer:latest",
                secretEnvironment: [
                    .init("api-key", secret: "first"),
                    .init("API_KEY", secret: "second"),
                ],
                context: makeContext()
            )
        }
    }

    @Test("Cloud Run sidecars reject duplicate normalized secret names")
    func duplicateSidecarSecretEnvironmentNames() async {
        await #expect(processExitsWith: .failure) {
            _ = GCP.CloudRunService.Sidecar(
                "collector",
                image: "us-docker.pkg.dev/example/collector:latest",
                secretEnvironment: [
                    .init("api-key", secret: "first"),
                    .init("API_KEY", secret: "second"),
                ]
            )
        }
    }
}
