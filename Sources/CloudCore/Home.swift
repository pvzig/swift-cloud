import Foundation

public protocol HomeProviderItem: Codable, Sendable {}

public struct HomeProviderPassphrase: HomeProviderItem {
    public let password: String

    fileprivate init() throws {
        self.password = try Data.random(length: 32).hexEncodedString()
    }
}

public protocol HomeProvider: Sendable {
    func bootstrap(with context: Context) async throws

    /// Returns whether `error` means that a requested home item does not exist.
    ///
    /// Providers must distinguish absence from authentication, authorization,
    /// transport, and tooling failures. Swift Cloud only creates replacement
    /// state for an item that is known to be absent.
    func isItemNotFoundError(_ error: any Error) -> Bool

    func passphrase(with context: Context) async throws -> String

    func putItem<T: HomeProviderItem>(_ item: T, fileName: String, with context: Context) async throws

    func getItem<T: HomeProviderItem>(fileName: String, with context: Context) async throws -> T
}

extension HomeProvider {
    public func isItemNotFoundError(_ error: any Error) -> Bool {
        false
    }

    public func passphrase(with context: Context) async throws -> String {
        let fileName = "passphrase"
        do {
            let password: HomeProviderPassphrase = try await getItem(
                fileName: fileName,
                with: context
            )
            return password.password
        } catch let error where isItemNotFoundError(error) {
            let passphrase = try HomeProviderPassphrase()
            try await putItem(passphrase, fileName: fileName, with: context)
            return passphrase.password
        }
    }
}

extension HomeProvider {
    public func contextualFileName(_ fileName: String, with context: Context) -> String {
        "\(context.name)/\(context.stage)/\(tokenize(fileName)).json"
    }
}

extension HomeProvider {
    private func localStatePath(context: Context) -> String {
        "\(Context.cloudDirectory)/.pulumi/stacks/\(context.name)/\(context.stage).json"
    }

    internal func hasLocalState(context: Context) -> Bool {
        FileManager.default.fileExists(atPath: localStatePath(context: context))
    }

    internal func pullState(context: Context) async throws {
        do {
            let state: AnyCodable = try await getItem(fileName: "state", with: context)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try Files.createFile(atPath: localStatePath(context: context), contents: data)
        } catch let error where isItemNotFoundError(error) {
            return
        }
    }

    internal func pushState(context: Context) async throws {
        let data = try Files.readFile(atPath: localStatePath(context: context))
        let state = try JSONDecoder().decode(AnyCodable.self, from: data)
        try await putItem(state, fileName: "state", with: context)
    }
}

extension AnyCodable: HomeProviderItem {}
