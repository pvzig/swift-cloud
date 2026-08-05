import CloudCore

extension GCP {
    public struct GetProject: Sendable {
        public let id: String
        public let name: String
        public let number: String
        public let projectId: String
    }

    public static func getProject(
        _ projectID: String? = nil,
        context: Context = .current
    ) -> Output<GetProject> {
        let arguments: [String: Any] = projectID.map { ["projectId": $0] } ?? [:]
        return Variable<GetProject>.invoke(
            name: "\(projectID ?? context.gcpProjectID)-project",
            function: "gcp:organizations:getProject",
            arguments: arguments,
            context: context
        ).output
    }
}
