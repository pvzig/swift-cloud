import CloudCore
import Foundation

extension GCP {
    /// Persists Swift Cloud passphrases and local Pulumi snapshots in Cloud Storage.
    ///
    /// The implementation uses the authenticated `gcloud storage` CLI through
    /// Swift Cloud's existing subprocess boundary. It does not retain mutable
    /// process state and is safe to use across asynchronous command lifetimes.
    public struct Home: HomeProvider {
        typealias Command = @Sendable ([String]) async throws -> (stdout: String, stderr: String)

        private let projectID: String
        private let location: Region
        private let runCommand: Command

        public init(projectID: String, location: Region = .usCentral1) {
            self.init(projectID: projectID, location: location) { arguments in
                try await shellOut(to: .name("gcloud"), arguments: arguments)
            }
        }

        init(
            projectID: String,
            location: Region,
            runCommand: @escaping Command
        ) {
            self.projectID = projectID
            self.location = location
            self.runCommand = runCommand
        }

        public func bootstrap(with context: Context) async throws {
            do {
                _ = try await runCommand([
                    "storage", "buckets", "describe", storageURL,
                    "--project", projectID,
                ])
            } catch let ShellError.terminated(_, stderr)
                where stderr.localizedCaseInsensitiveContains("not found")
                || stderr.localizedCaseInsensitiveContains("404")
            {
                _ = try await runCommand([
                    "--quiet", "storage", "buckets", "create", storageURL,
                    "--project", projectID,
                    "--location", location.rawValue,
                    "--uniform-bucket-level-access",
                    "--public-access-prevention",
                ])
            }
        }

        public func putItem<T: HomeProviderItem>(
            _ item: T,
            fileName: String,
            with context: Context
        ) async throws {
            let temporaryFile = try temporaryFileURL(fileName: fileName)
            defer { try? FileManager.default.removeItem(at: temporaryFile.deletingLastPathComponent()) }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(item).write(to: temporaryFile)

            _ = try await runCommand([
                "--quiet", "storage", "cp", temporaryFile.path,
                objectURL(fileName: fileName, context: context),
            ])
        }

        public func getItem<T: HomeProviderItem>(
            fileName: String,
            with context: Context
        ) async throws -> T {
            let temporaryFile = try temporaryFileURL(fileName: fileName)
            defer { try? FileManager.default.removeItem(at: temporaryFile.deletingLastPathComponent()) }

            _ = try await runCommand([
                "--quiet", "storage", "cp",
                objectURL(fileName: fileName, context: context),
                temporaryFile.path,
            ])
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: temporaryFile))
        }

        private var bucketName: String {
            "swift-cloud-assets-\(tokenize(projectID))"
        }

        private var storageURL: String {
            "gs://\(bucketName)"
        }

        private func objectURL(fileName: String, context: Context) -> String {
            "\(storageURL)/\(contextualFileName(fileName, with: context))"
        }

        private func temporaryFileURL(fileName: String) throws -> URL {
            let directory = URL.temporaryDirectory.appending(
                path: "swift-cloud-gcp-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appending(path: tokenize(fileName)).appendingPathExtension("json")
        }
    }
}

extension HomeProvider where Self == GCP.Home {
    public static func gcp(
        projectID: String,
        location: GCP.Region = .usCentral1
    ) -> Self {
        .init(projectID: projectID, location: location)
    }
}
