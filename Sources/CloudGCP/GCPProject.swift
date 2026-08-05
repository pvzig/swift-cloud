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
}
