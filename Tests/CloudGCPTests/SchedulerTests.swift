import Testing

@testable import CloudCore
@testable import CloudGCP

@Suite("GCP Scheduler")
struct SchedulerTests {
    @Test("Scheduler invokes Cloud Run with an OIDC token and retry policy")
    func cloudRunTarget() throws {
        let context = makeContext()
        let schedulerIdentity = GCP.ServiceAccount("scheduler", context: context)
        let service = GCP.CloudRunService(
            "worker",
            image: "us-docker.pkg.dev/example/worker:latest",
            context: context
        )
        _ = GCP.SchedulerJob(
            "worker-tick",
            schedule: "*/5 * * * *",
            target: .cloudRun(
                service,
                path: "/internal/tick",
                serviceAccount: schedulerIdentity
            ),
            context: context
        )

        let job = try properties(type: "gcp:cloudscheduler:Job", in: context)
        #expect(job["schedule"] as? String == "*/5 * * * *")
        let target = try #require(job["httpTarget"] as? [String: Any])
        #expect(target["uri"] as? String == "${testing-worker.uri}/internal/tick")
        let token = try #require(target["oidcToken"] as? [String: Any])
        #expect(token["serviceAccountEmail"] as? String == "${testing-scheduler-service-account.email}")
        #expect(token["audience"] as? String == "${testing-worker.uri}")

        let retry = try #require(job["retryConfig"] as? [String: Any])
        #expect(retry["retryCount"] as? Int == 3)
        #expect(context.store.resources.contains { $0.type == "gcp:cloudrunv2:ServiceIamMember" })
    }

    @Test("Building a target does not grant access until a job schedules it")
    func targetsAreInert() throws {
        let context = makeContext()
        let schedulerIdentity = GCP.ServiceAccount("scheduler", context: context)
        let service = GCP.CloudRunService(
            "worker",
            image: "us-docker.pkg.dev/example/worker:latest",
            context: context
        )

        let target = GCP.SchedulerJob.Target.cloudRun(service, serviceAccount: schedulerIdentity)
        #expect(context.store.resources.contains { $0.type == "gcp:cloudrunv2:ServiceIamMember" } == false)

        _ = GCP.SchedulerJob(
            "worker-tick",
            schedule: "*/5 * * * *",
            target: target,
            context: context
        )
        #expect(context.store.resources.contains { $0.type == "gcp:cloudrunv2:ServiceIamMember" })
    }
}
