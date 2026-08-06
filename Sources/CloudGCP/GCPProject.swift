import CloudCore

public protocol GCPProject: Project {
    var projectID: String { get }
    var region: GCP.Region { get }
}

extension GCPProject {
    public var region: GCP.Region {
        .usCentral1
    }

    public var providers: [Provider] {
        [.gcp(projectID: projectID, region: region)]
    }

    public var home: any HomeProvider {
        .gcp(projectID: projectID, location: region)
    }
}

extension Context {
    public var gcpProjectID: String {
        guard let project = project as? any GCPProject else {
            fatalError("Project definition does not conform to GCPProject")
        }
        return project.projectID
    }

    public var gcpRegion: GCP.Region {
        guard let project = project as? any GCPProject else {
            fatalError("Project definition does not conform to GCPProject")
        }
        return project.region
    }

    /// The stage token used to build Google Cloud physical resource names.
    ///
    /// Google Cloud requires resource names to match `[a-z]([-a-z0-9]*[a-z0-9])?`,
    /// but stages default to the current git branch, which frequently starts with
    /// a ticket number. Prefixing those stages keeps generated names valid instead
    /// of failing every resource in the stack at apply time.
    public var gcpStage: String {
        guard let first = stage.first, first.isLetter else {
            return "s\(stage.isEmpty ? "" : "-\(stage)")"
        }
        return stage
    }
}
