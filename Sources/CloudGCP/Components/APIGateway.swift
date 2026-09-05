import CloudCore
import Foundation

extension GCP {
    /// A managed API Gateway deployment backed by OpenAPI or gRPC configuration.
    public struct APIGateway: GCPComponent {
        public let api: Resource
        public let configuration: Resource
        public let gateway: Resource
        public let serviceIdentity: ServiceIdentity
        public let serviceAccount: ServiceAccount
        public let tokenCreatorGrant: Resource

        public var name: Output<String> {
            gateway.name
        }

        public var hostname: Output<String> {
            gateway.output.keyPath("defaultHostname")
        }

        public var url: Output<String> {
            "https://\(hostname)"
        }

        public init(
            _ name: String,
            document: Document,
            serviceAccount: ServiceAccount,
            backends: [CloudRunService] = [],
            location: Region? = nil,
            displayName: String? = nil,
            options: Resource.Options? = nil,
            context: Context = .current
        ) {
            self.serviceAccount = serviceAccount
            let apiID = tokenize(context.gcpStage, name, maxLength: 63)

            api = Resource(
                name: "\(name)-api",
                type: "gcp:apigateway:Api",
                properties: [
                    "project": context.gcpProjectID,
                    "apiId": apiID,
                    "displayName": displayName,
                ],
                options: options,
                context: context
            )

            serviceIdentity = ServiceIdentity.shared(
                .apiGateway,
                options: options,
                context: context
            )
            // Owned by the service account so several gateways can share one backend
            // identity without declaring competing grants for the same binding.
            tokenCreatorGrant = serviceAccount.serviceAccountRole(
                .serviceAccountTokenCreator,
                to: serviceIdentity.member
            )
            for backend in backends {
                backend.allowInvocation(from: serviceAccount)
            }

            configuration = Resource(
                name: "\(name)-configuration",
                type: "gcp:apigateway:ApiConfig",
                properties: [
                    "project": context.gcpProjectID,
                    "api": api.output.keyPath("apiId"),
                    // API configs are immutable. Deriving the id from the document
                    // and backend identity means changing either creates a new config
                    // instead of trying to recreate an in-use id, which GCP rejects.
                    "apiConfigId": tokenize(
                        apiID,
                        "config",
                        digest(document.fingerprint, serviceAccount.email),
                        maxLength: 63
                    ),
                    "displayName": displayName,
                    "gatewayConfig": [
                        "backendConfig": [
                            "googleServiceAccount": serviceAccount.email
                        ]
                    ],
                    "openapiDocuments": document.openapiDocuments,
                    "grpcServices": document.grpcServices,
                    "managedServiceConfigs": document.managedServiceConfigurations,
                ],
                options: options,
                context: context,
                dependsOn: [api, tokenCreatorGrant]
            )

            gateway = Resource(
                name: name,
                type: "gcp:apigateway:Gateway",
                properties: [
                    "project": context.gcpProjectID,
                    "region": GCP.resolvedRegion(location, options: options, context: context).rawValue,
                    "gatewayId": apiID,
                    "displayName": displayName,
                    "apiConfig": configuration.id,
                ],
                options: options,
                context: context,
                dependsOn: [configuration]
            )
        }
    }
}

extension GCP.APIGateway {
    /// API configuration contents are base64 encoded for the API Gateway API.
    public enum Document: Sendable {
        case grpc(
            fileDescriptorSet: Data,
            descriptorPath: String = "api_descriptor.pb",
            serviceConfiguration: String,
            configurationPath: String = "api_config.yaml"
        )
        case openAPI(contents: String, path: String = "openapi.yaml")

        /// A stable representation of everything that makes this configuration
        /// distinct, used to give each revision its own immutable config id.
        fileprivate var fingerprint: String {
            switch self {
            case .grpc(let fileDescriptorSet, let descriptorPath, let configuration, let configurationPath):
                "grpc:\(descriptorPath):\(fileDescriptorSet.base64EncodedString()):\(configurationPath):\(configuration)"
            case .openAPI(let contents, let path):
                "openapi:\(path):\(contents)"
            }
        }

        fileprivate var openapiDocuments: AnyEncodable? {
            switch self {
            case .grpc:
                nil
            case .openAPI(let contents, let path):
                [
                    [
                        "document": [
                            "path": path,
                            "contents": ["fn::toBase64": contents],
                        ]
                    ]
                ]
            }
        }

        fileprivate var grpcServices: AnyEncodable? {
            switch self {
            case .grpc(let fileDescriptorSet, let descriptorPath, _, _):
                [
                    [
                        "fileDescriptorSet": [
                            "path": descriptorPath,
                            "contents": fileDescriptorSet.base64EncodedString(),
                        ]
                    ]
                ]
            case .openAPI:
                nil
            }
        }

        fileprivate var managedServiceConfigurations: AnyEncodable? {
            switch self {
            case .grpc(_, _, let serviceConfiguration, let configurationPath):
                [
                    [
                        "path": configurationPath,
                        "contents": ["fn::toBase64": serviceConfiguration],
                    ]
                ]
            case .openAPI:
                nil
            }
        }
    }
}
