import CloudCore

extension GCP {
    /// A Firestore database and its declared composite indexes.
    public struct FirestoreDatabase: GCPComponent {
        public let database: Resource
        public let indexes: [Resource]
        public let databaseID: String

        public var name: Output<String> {
            database.name
        }

        public init(
            _ name: String,
            databaseID: String = "(default)",
            locationID: String? = nil,
            mode: Mode = .native,
            edition: Edition = .standard,
            concurrencyMode: ConcurrencyMode = .pessimistic,
            pointInTimeRecoveryEnabled: Bool = true,
            deletionProtection: Bool? = nil,
            indexes: [Index] = [],
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            precondition(databaseID.isEmpty == false, "databaseID must not be empty")
            precondition(
                edition == .standard || mode == .native,
                "Firestore Enterprise edition requires native mode"
            )
            self.databaseID = databaseID

            database = Resource(
                name: name,
                type: "gcp:firestore:Database",
                properties: [
                    "project": context.gcpProjectID,
                    "name": databaseID,
                    "locationId": locationID ?? context.gcpRegion.rawValue,
                    "type": mode.rawValue,
                    "databaseEdition": edition.rawValue,
                    "concurrencyMode": concurrencyMode.rawValue,
                    "pointInTimeRecoveryEnablement": pointInTimeRecoveryEnabled
                        ? "POINT_IN_TIME_RECOVERY_ENABLED"
                        : "POINT_IN_TIME_RECOVERY_DISABLED",
                    "deleteProtectionState": (deletionProtection ?? context.isProduction)
                        ? "DELETE_PROTECTION_ENABLED"
                        : "DELETE_PROTECTION_DISABLED",
                ],
                options: options,
                context: context
            )
            let databaseResource = database

            self.indexes = indexes.enumerated().map { offset, index in
                Resource(
                    name: "\(name)-\(index.collection)-index-\(offset + 1)",
                    type: "gcp:firestore:Index",
                    properties: [
                        "project": context.gcpProjectID,
                        "database": databaseID,
                        "collection": index.collection,
                        "queryScope": index.queryScope.rawValue,
                        "fields": index.fields.map(\.properties),
                    ],
                    options: options,
                    context: context,
                    dependsOn: [databaseResource]
                )
            }
        }
    }
}

extension GCP.FirestoreDatabase {
    public enum Mode: String, Sendable {
        case datastore = "DATASTORE_MODE"
        case native = "FIRESTORE_NATIVE"
    }

    public enum Edition: String, Sendable {
        case enterprise = "ENTERPRISE"
        case standard = "STANDARD"
    }

    public enum ConcurrencyMode: String, Sendable {
        case optimistic = "OPTIMISTIC"
        case optimisticWithEntityGroups = "OPTIMISTIC_WITH_ENTITY_GROUPS"
        case pessimistic = "PESSIMISTIC"
    }

    public struct Index: Sendable {
        public let collection: String
        public let queryScope: QueryScope
        public let fields: [Field]

        public init(
            collection: String,
            queryScope: QueryScope = .collection,
            fields: [Field]
        ) {
            precondition(collection.isEmpty == false, "index collections must not be empty")
            precondition(fields.isEmpty == false, "indexes require at least one field")
            self.collection = collection
            self.queryScope = queryScope
            self.fields = fields
        }
    }

    public enum QueryScope: String, Sendable {
        case collection = "COLLECTION"
        case collectionGroup = "COLLECTION_GROUP"
        case collectionRecursive = "COLLECTION_RECURSIVE"
    }

    public enum Field: Sendable {
        case arrayContains(String)
        case ascending(String)
        case descending(String)

        fileprivate var properties: AnyEncodable {
            switch self {
            case .arrayContains(let path):
                ["fieldPath": path, "arrayConfig": "CONTAINS"]
            case .ascending(let path):
                ["fieldPath": path, "order": "ASCENDING"]
            case .descending(let path):
                ["fieldPath": path, "order": "DESCENDING"]
            }
        }
    }
}

extension GCP.FirestoreDatabase: GCPLinkable {
    public var actions: [String] {
        [GCP.IAMRole.datastoreUser.rawValue]
    }

    public var resources: [Output<String>] {
        [database.id]
    }

    public var properties: LinkProperties? {
        .init(
            type: "firestore",
            name: database.chosenName,
            properties: [
                "name": name,
                "project_id": database.context.gcpProjectID,
            ]
        )
    }

    public func grantAccess(to serviceAccount: GCP.ServiceAccount) {
        serviceAccount.grantProjectRole(.datastoreUser)
    }
}
