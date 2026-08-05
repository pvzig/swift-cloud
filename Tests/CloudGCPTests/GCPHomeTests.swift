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

        func run(_ arguments: [String]) async throws -> (stdout: String, stderr: String) {
            commands.append(arguments)

            if arguments.contains("describe"), bucketExists == false {
                throw ShellError.terminated(errorCode: 1, stderr: "404 bucket not found")
            }
            if arguments.contains("create") {
                bucketExists = true
            }
            if arguments.contains("cp") {
                let source = arguments[arguments.count - 2]
                let destination = arguments[arguments.count - 1]
                if source.hasPrefix("gs://") {
                    guard let data = objects[source] else {
                        throw ShellError.terminated(errorCode: 1, stderr: "404 object not found")
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
}
