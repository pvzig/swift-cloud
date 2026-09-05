import Foundation
import Testing

@testable import CloudCore
@testable import CloudGCP

@Suite("GCP home state")
struct GCPHomeTests {
    struct Item: HomeProviderItem, Equatable {
        let value: String
    }

    actor CommandRecorder {
        private(set) var commands: [[String]] = []
        private var bucketExists = false
        private var objects: [String: Data] = [:]
        private let createConflict: Bool
        private let downloadFailure: String?

        init(createConflict: Bool = false, downloadFailure: String? = nil) {
            self.createConflict = createConflict
            self.downloadFailure = downloadFailure
        }

        func run(_ arguments: [String]) async throws -> (stdout: String, stderr: String) {
            commands.append(arguments)

            if arguments.contains("describe"), bucketExists == false {
                throw ShellError.terminated(errorCode: 1, stderr: "404 bucket not found")
            }
            if arguments.contains("create") {
                bucketExists = true
                if createConflict {
                    throw ShellError.terminated(errorCode: 1, stderr: "HTTP 409 already exists")
                }
            }
            if arguments.contains("cp") {
                let source = arguments[arguments.count - 2]
                let destination = arguments[arguments.count - 1]
                if source.hasPrefix("gs://") {
                    if let downloadFailure {
                        throw ShellError.terminated(errorCode: 1, stderr: downloadFailure)
                    }
                    guard let data = objects[source] else {
                        throw ShellError.terminated(
                            errorCode: 1,
                            stderr:
                                "ERROR: (gcloud.storage.cp) The following URLs matched no objects or files:\n\(source)"
                        )
                    }
                    try data.write(to: URL(filePath: destination))
                } else {
                    objects[destination] = try Data(contentsOf: URL(filePath: source))
                }
            }
            return ("", "")
        }
    }

    @Test("Home creates its bucket and round-trips JSON through injected gcloud commands")
    func roundTrip() async throws {
        let recorder = CommandRecorder()
        let home = GCP.Home(projectID: "example-project", location: .usEast1) { arguments in
            try await recorder.run(arguments)
        }
        let context = makeContext()
        let expected = Item(value: "persisted")

        try await home.bootstrap(with: context)
        try await home.putItem(expected, fileName: "fixture", with: context)
        let actual: Item = try await home.getItem(fileName: "fixture", with: context)

        #expect(actual == expected)
        let commands = await recorder.commands
        #expect(commands.contains { $0.contains("create") })
        #expect(commands.filter { $0.contains("cp") }.count == 2)
    }

    @Test("Home retries describe after losing a concurrent bucket-create race")
    func concurrentBootstrap() async throws {
        let recorder = CommandRecorder(createConflict: true)
        let home = GCP.Home(projectID: "example-project", location: .usEast1) { arguments in
            try await recorder.run(arguments)
        }

        try await home.bootstrap(with: makeContext())

        let commands = await recorder.commands
        #expect(commands.filter { $0.contains("describe") }.count == 2)
        #expect(commands.filter { $0.contains("create") }.count == 1)
    }

    @Test("A missing passphrase is created once and then reused")
    func missingPassphrase() async throws {
        let recorder = CommandRecorder()
        let home = GCP.Home(projectID: "example-project", location: .usCentral1) { arguments in
            try await recorder.run(arguments)
        }
        let context = makeContext()

        let first = try await home.passphrase(with: context)
        let second = try await home.passphrase(with: context)

        #expect(first == second)
        let commands = await recorder.commands
        #expect(commands.filter { $0.contains("cp") }.count == 3)
    }

    @Test("A fresh home can start without an existing stack snapshot")
    func missingState() async throws {
        let recorder = CommandRecorder()
        let home = GCP.Home(projectID: "example-project", location: .usCentral1) { arguments in
            try await recorder.run(arguments)
        }
        let context = makeContext()

        try await home.bootstrap(with: context)
        try await home.pullState(context: context)
        _ = try await home.passphrase(with: context)

        let commands = await recorder.commands
        let transfers = commands.filter { $0.contains("cp") }
        #expect(transfers.count == 3)
        #expect(transfers.filter { $0[$0.count - 2].hasPrefix("gs://") }.count == 2)
    }

    @Test(
        "Failed home reads never replace state or passphrases",
        arguments: ["HTTP 403 permission denied", "HTTP 500 internal server error", "Connection reset by peer"]
    )
    func passphraseFailureIsFailClosed(diagnostic: String) async {
        let recorder = CommandRecorder(downloadFailure: diagnostic)
        let home = GCP.Home(projectID: "example-project", location: .usCentral1) { arguments in
            try await recorder.run(arguments)
        }

        do {
            _ = try await home.passphrase(with: makeContext())
            Issue.record("Expected the authorization failure to propagate")
        } catch let ShellError.terminated(_, stderr) {
            #expect(stderr == diagnostic)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            try await home.pullState(context: makeContext())
            Issue.record("Expected the state read failure to propagate")
        } catch let ShellError.terminated(_, stderr) {
            #expect(stderr == diagnostic)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let commands = await recorder.commands
        let transfers = commands.filter { $0.contains("cp") }
        #expect(transfers.count == 2)
        #expect(transfers.allSatisfy { $0[$0.count - 2].hasPrefix("gs://") })
    }
}
