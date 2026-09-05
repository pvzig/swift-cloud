import Testing

@testable import CloudCore

@Suite("Pulumi Tests")
struct PulumiTests {
    @Test func setupPulumi() async throws {
        let client = Pulumi.Client(context: "testing")
        try await client.setup()
        #expect(client.isSetup)
    }

    @Test("Pulumi preserves the caller PATH for provider credential helpers")
    func environmentPath() {
        let client = Pulumi.Client(context: "testing")
        let path = "/opt/homebrew/share/google-cloud-sdk/bin:/usr/bin:/bin"
        let environment = client.environment(base: ["PATH": path])

        #expect(environment["PATH"] == path)
        #expect(environment["PULUMI_SKIP_UPDATE_CHECK"] == "true")
    }
}
