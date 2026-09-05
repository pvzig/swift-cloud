# Swift Cloud

Swift Infrastructure as Code

The fastest way to build and deploy server side Swift applications.

Swift Cloud is based on the premise that infrastructure should be defined along
side your application, in the same language as your application. In our case,
Swift. Define a new target, describe your infrastructure, and deploy it with a
single command. There's no Dockerfiles, no Terrafrom configurations, no Node.js
packages. Everything is defined in Swift and the complex configuration is
handled behind the scenes, using modern architecture best practices.

```swift
let jobHandler = AWS.Function(
    "job-handler",
    targetName: "JobProcessor",
    memory: 512,
    timeout: .seconds(10)
)

let queue = AWS.Queue("job-queue")

queue.subscribe(jobHandler)

let server = AWS.WebServer(
    "hummingbird-server",
    targetName: "App",
    concurrency: 1,
    autoScaling: .init(
        maximumConcurrency: 10,
        metrics: [.cpu(50), .memory(50)]
    )
)

server.link(queue)
```

```sh
swift run Infra deploy --stage production
```

## How it works

The Swift Cloud package is powered by [Pulumi](https://www.pulumi.com).
Specifically, the SDK vends Swift components that are compiled into Pulumi YAML
files, and then the Pulumi CLI is used to deploy your application. You do not
need a Pulumi account to use Swift Cloud, nor do you need to install Pulumi CLI
on your machine. Everything is managed by the SDK and written to a `.cloud`
directory in your project.

## Get Started

### Prepare your environment

#### Setup Docker

In order to use Swift Cloud you need to have Docker installed on your machine.
This is a short term limitation until Swift 6 where we will be able to natively
cross-compile to Linux and other SDKs.

If you're on a Mac the easiest way to install Docker is
[OrbStack](https://orbstack.dev). Simply download OrbStack and run the
installer.

#### Setup AWS

You will need to have an AWS account and AWS credentials loaded on your machine
or in the typical environment variables.

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
```

You can also provide a `.env` file in the root of your project with the same
relevant variables.

If you're on a Mac the easiest way to manage your AWS credentials is
[Leapp](https://www.leapp.cloud).

You can also use the AWS CLI to configure your credentials:

```bash
aws configure
```

#### Setup GCP

Google Cloud resources use Application Default Credentials. Authenticate the
Pulumi GCP provider, then configure Docker for the Artifact Registry hostname in
the region you deploy to:

```bash
gcloud auth application-default login
gcloud auth configure-docker us-east1-docker.pkg.dev
```

The deploying identity needs permission to activate the APIs and create the
resources declared by the project.

### Add to your project

```swift
dependencies: [
    .package(url: "https://github.com/swift-cloud/swift-cloud.git", branch: "main")
]
```

### Define your infrastructure

Swift Cloud works by declaring your infrastructure as Swift code. To do this you
must create a new executable target in the same package as your application.

Start by defining a new executable target in your `Package.swift` file:

```swift
targets: [
    ...
    .executableTarget(
        name: "Infra",
        dependencies: [
            .product(name: "Cloud", package: "swift-cloud")
        ]
    )
]
```

Next, inside your `Sources` directory create a new folder called `Infra`.

Finally, add a new Swift file called `Project.swift`:

```swift
import Cloud

@main
struct SwiftCloudDemo: AWSProject {
    func build() async throws -> Outputs {
        let server = AWS.WebServer(
            "my-vapor-web-server",
            targetName: "App",
            concurrency: 1,
            autoScaling: .init(
                maximumConcurrency: 10,
                metrics: [.cpu(50), .memory(50)]
            )
        )

        return Outputs([
            "url": server.url,
        ])
    }
}
```

### Deploy your project

```bash
swift run Infra deploy --stage production
```

## Commands

Swift Cloud is invoked directly from your Swift package. You can run the
following commands:

### Deploy

Deploy your infrastructure:

```bash
swift run Infra deploy --stage production
```

### Remove

Remove all resources:

```bash
swift run Infra remove --stage development
```

### Preview

Preview changes before deploying:

```bash
swift run Infra preview --stage development
```

### Outputs

Show the outputs of your deployment:

```bash
swift run Infra outputs --stage development
```

### Cancel

Cancel a deployment:

```bash
swift run Infra cancel --stage development
```

## Home

Swift Cloud allows you to deploy infrastructure across multiple cloud providers.
In order to handle incremental changes to your infrastructure, Swift Cloud must
store your underlying configuration in a durable location so it can be
referenced anytime you run a deploy, whether from your local machine or a CI/CD
pipeline.

We abstracted this concept into a `HomeProvider` protocol, and allow you to
decide where your configuration is stored. By default, Swift Cloud uses the AWS
S3 service to store your configuration, but you can easily swap this out for any
other provider that supports the `HomeProvider` protocol.

For quick prototyping, you can use the `Home.Local` provider, which stores your
configuration in a local file. This is great for testing and development, but
it's not recommended for production use.

```swift
import Cloud

@main
struct SwiftCloudDemo: AWSProject {

    // Override the default home provider with a local provider
    let home = Home.Local()

    func build() async throws -> Outputs {...}
}
```

## Components

### AWS

#### WebServer

This component creates a high performance web server using an application load
balancer, auto-scaling group, and Fargate. Everything is fully managed and
scales automatically based on your configuration.

```swift
let server = AWS.WebServer(
    "my-vapor-web-server",
    targetName: "App",
    concurrency: 1,
    autoScaling: .init(
        maximumConcurrency: 10,
        metrics: [.cpu(50), .memory(50)]
    )
)
```

#### Function

```swift
let lambda = AWS.Function(
    "my-lambda-function",
    targetName: "App",
    url: .enabled(cors: true),
    memory: 512,
    timeout: .seconds(10)
)

// Optional: build with the static Linux SDK instead of Docker
let staticLambda = AWS.Function(
    "my-static-lambda-function",
    targetName: "App",
    runtime: .al2023,
    build: .staticLinuxSDK
)
```

#### API Gateway

This component creates an Amazon API Gateway v2 HTTP API that routes requests to
one or more Lambda functions. It's a lightweight alternative to a full web
server for serverless HTTP APIs.

```swift
let api = AWS.APIGateway("my-api")
    .route("$default", function: myFunction)

return Outputs([
    "url": api.url
])
```

You can route different HTTP methods and paths to different functions:

```swift
let api = AWS.APIGateway("my-api")
    .route("GET /users", function: listUsers)
    .route("POST /users", function: createUser)
    .route("DELETE /users/{id}", function: deleteUser)
```

Custom domains are supported with any DNS provider:

```swift
// Route53
let api = AWS.APIGateway(
    "my-api",
    domainName: .init(hostname: "api.example.com", dns: .aws(zoneName: "example.com"))
)
.route("$default", function: myFunction)

// Cloudflare
let api = AWS.APIGateway(
    "my-api",
    domainName: .init(hostname: "api.example.com", dns: .cloudflare(zoneName: "example.com"))
)
.route("$default", function: myFunction)
```

Access logs are written to CloudWatch automatically. You can customise the log format using the built-in presets or provide your own:

```swift
// Default JSON format (used when logFormat is omitted)
AWS.APIGateway("my-api", logFormat: .default)

// Common Log Format (CLF)
AWS.APIGateway("my-api", logFormat: .clf)

// Custom format using API Gateway $context variables
AWS.APIGateway("my-api", logFormat: "$context.requestId $context.status $context.routeKey")
```

#### CDN

This component creates a CDN that sits in front of your application. It can be
used to cache your application assets, or to serve your application from a
custom domain.

```swift
let cdn = AWS.CDN(
    "my-cdn",
    origins: .webServer(server)
)
```

You can also route traffic on different paths to different resources:

```swift
let cdn = AWS.CDN(
    "my-cdn",
    origins: [
        .function(function, path: "/api/*"),
        .webServer(server, path: "*")
    ]
)
```

And of course you can use a custom domain:

```swift
let cdn = AWS.CDN(
    "my-cdn",
    origins: .function(function),
    domainName: .init("www.example.com")
)
```

#### Bucket

```swift
let bucket = AWS.Bucket("my-s3-bucket")
```

#### Queue

```swift
let queue = AWS.Queue("my-sqs-queue")

// Subscribe a lambda function to the queue to process messages
queue.subscribe(
    AWS.Function("my-lambda-function", targetName: "App")
)
```

#### DynamoDB

```swift
let table = AWS.DynamoDB(
    "MyTable",
    primaryIndex: .init(
        partitionKey: ("type", .string),
        sortKey: ("id", .string)
    )
)

// Link the table to a function or web server
function.link(table)
```

#### Cache

```swift
let vpc = AWS.VPC("my-vpc")

let cache = AWS.Cache(
    "my-valkey-cache",
    engine: .valkey(), // or .redis() or .memcached()
    vpc: .private(vpc)
)

// Allow the function or web server to connect to the cache
function.link(cache)
```

#### SQL Database

```swift
let database = AWS.SQLDatabase(
    "my-postgres-database",
    engine: .postgres(),
    vpc: .private(vpc)
)

// Allow the function or web server to connect to the database
function.link(database)
```

#### Aurora DSQL

```swift
let east = AWS.DSQL.Cluster(
    "orders-east",
    region: "us-east-1",
    multiRegion: .enabled(witnessRegion: "us-west-2")
)

let west = AWS.DSQL.Cluster(
    "orders-west",
    region: "us-east-2",
    multiRegion: .enabled(witnessRegion: "us-west-2")
)

// Creates both directional aws:dsql:ClusterPeering resources
east.peer(with: west)
```

#### Topic

```swift
let topic = AWS.Topic("my-sns-topic")

// Subscribe a lambda function to the topic to process events
topic.subscribe(
    AWS.Function("my-lambda-function", targetName: "App")
)
```

#### Cron

```swift
let cron = AWS.Cron(
    "my-cron-job",
    schedule: .rate(.minutes(5))
)

// Invoke the function when the cron job runs
cron.invoke(
    AWS.Function("my-lambda-function", targetName: "App")
)
```

#### Domain Name

The `DomainName` construct manages a TLS certificate and the necessary
validation, and can be linked to a `WebServer` to provide a fully managed domain
name.

> [!IMPORTANT]
> SwiftCloud supports 3 providers for domains: **AWS**, **Cloudflare**, and **Vercel**.

```swift
let domainName = DomainName(
    hostname: "www.example.com",
    dns: .aws(zoneName: "example.com")
)

let server = AWS.WebServer(
    "my-vapor-web-server",
    targetName: "App",
    domainName: domainName
)

return Outputs([
    // Now server url will be `https://www.example.com`
    "url": server.url
])
```

### GCP

GCP support follows the same provider-specific component model as AWS. Google
API activation is explicit and should be declared once per project.

Authenticate Pulumi with [Application Default Credentials](https://cloud.google.com/docs/authentication/provide-credentials-adc)
and configure Docker for each Artifact Registry hostname before deploying an
image, for example `gcloud auth configure-docker us-east1-docker.pkg.dev`.
`GCPProject` stores its passphrase and local Pulumi snapshot in a
project-specific Cloud Storage bucket through the authenticated `gcloud storage`
command. Override `home` with `.local()` only when local-only state is intentional.

Every GCP infrastructure executable must declare the Google Cloud project ID;
the region defaults to `us-central1` when omitted:

```swift
import Cloud

@main
struct Infrastructure: GCPProject {
    let projectID = "my-google-cloud-project"
    let region = GCP.Region.usEast1

    func build() async throws -> Outputs {
        // Declare resources here.
        [:]
    }
}
```

Declare the APIs required by your components and use them as dependencies so
activation completes before Pulumi creates the infrastructure:

```swift
let apis: [any ResourceProvider] = [
    GCP.ProjectService(.artifactRegistry),
    GCP.ProjectService(.cloudRun),
]
let options = Resource.Options.dependsOn(apis)
```

#### Cloud Run Service

This component builds a Swift executable into an Artifact Registry image and
runs it as a managed Cloud Run service with configurable scaling, ingress,
networking, secrets, volumes, probes, and sidecars.

```swift
let runtimeIdentity = GCP.ServiceAccount("backend", options: options)
let repository = GCP.ArtifactRegistry("services", options: options)
let image = GCP.ContainerImage(
    "backend",
    targetName: "App",
    repository: repository
)

let service = GCP.CloudRunService(
    "backend",
    image: image.reference,
    serviceAccount: runtimeIdentity,
    protocol: .http2,
    scaling: .init(minimumInstances: 1, maximumInstances: 10),
    publicAccess: true,
    options: options
)
```

#### Cloud Run Job

This component runs a container to completion for batch and scheduled work.

```swift
let job = GCP.CloudRunJob(
    "daily-import",
    image: image.reference,
    serviceAccount: runtimeIdentity,
    taskCount: 4,
    parallelism: 2,
    timeout: .seconds(900)
)
```

#### Cloud Run Worker Pool

This component creates a continuously running worker pool for pull-based
workloads that do not serve HTTP requests.

```swift
let subscription = GCP.Subscription("events-subscription", topic: events)

let worker = GCP.CloudRunWorkerPool(
    "events-worker",
    image: image.reference,
    serviceAccount: runtimeIdentity,
    scaling: .automatic(maximumInstances: 10)
).link(subscription)
```

#### API Gateway

This component creates a managed Google Cloud API Gateway from an OpenAPI or
gRPC document and authorizes it to invoke its Cloud Run backends. The provider
generates a unique config ID for each immutable revision, including when an
interpolated backend URL or service-account email changes.

```swift
let gatewayIdentity = GCP.ServiceAccount("gateway")
let gateway = GCP.APIGateway(
    "public-api",
    document: .openAPI(contents: openAPIDocument),
    serviceAccount: gatewayIdentity,
    backends: [service]
)
```

#### Bucket

This component creates a Cloud Storage bucket with optional object versioning
and public read access.

```swift
let bucket = GCP.Bucket(
    "assets",
    storageClass: .standard,
    versioningEnabled: true
)

// Grant the Cloud Run service access and inject bucket metadata.
service.link(bucket)
```

#### Pub/Sub

`Topic` and `Subscription` provide asynchronous messaging with pull delivery,
OIDC-authenticated push delivery, retry policies, and dead-letter topics.
Subscriptions do not expire by default; pass `expiration: .after(...)` when
inactivity-based deletion is intentional.

```swift
let events = GCP.Topic(
    "events",
    messageRetention: .seconds(86_400)
)

let subscription = GCP.Subscription(
    "events-worker",
    topic: events,
    retryPolicy: .init(
        minimumBackoff: .seconds(10),
        maximumBackoff: .seconds(600)
    )
)

worker.link(subscription)
```

For authenticated push delivery, grant the Pub/Sub service identity token
creation access on the push service account and grant that account invocation
access to the receiving Cloud Run service.

#### Cloud Tasks Queue

This component creates an HTTP task queue with dispatch limits, retry policy,
OIDC authentication, and queue-scoped enqueuer access. Applications create the
individual tasks and their request payloads through the Cloud Tasks API.

```swift
let dispatcherIdentity = GCP.ServiceAccount("task-dispatcher")
let producerIdentity = GCP.ServiceAccount("task-producer")

let queue = GCP.TaskQueue(
    "background",
    rateLimits: .init(maximumConcurrentDispatches: 20),
    target: .cloudRun(service, serviceAccount: dispatcherIdentity)
).allowEnqueuing(from: producerIdentity)
```

#### Cloud Scheduler

This component schedules HTTP, Pub/Sub, Cloud Run service, or Cloud Run job
targets and creates the destination IAM grants for the convenience targets.

```swift
let schedulerIdentity = GCP.ServiceAccount("scheduler")

let schedule = GCP.SchedulerJob(
    "daily-import-schedule",
    schedule: "0 2 * * *",
    target: .cloudRunJob(job, serviceAccount: schedulerIdentity),
    timeZone: "America/New_York"
)
```

#### Eventarc Trigger

This component routes Google Cloud events to Cloud Run or Workflows and grants
the trigger identity permission to invoke its destination.

```swift
let eventIdentity = GCP.ServiceAccount("event-receiver")

let trigger = GCP.EventarcTrigger(
    "asset-created",
    eventType: "google.cloud.storage.object.v1.finalized",
    target: .cloudRun(service, path: "/events/storage"),
    serviceAccount: eventIdentity,
    criteria: [.init(attribute: "bucket", value: "assets")]
)
```

#### Cloud SQL

This component creates a PostgreSQL or MySQL Cloud SQL instance and logical
database with optional private networking, regional availability, IAM users,
and read replicas. It defaults to Enterprise edition, which supports the
default custom tier. Use `edition: .enterprisePlus` with a compatible
predefined `tier` to select Enterprise Plus; replicas use the same edition.

```swift
let vpc = GCP.VPC("main")

let database = GCP.SQLDatabase(
    "main",
    engine: .postgres16,
    databaseName: "app",
    availability: .regional,
    vpc: vpc,
    readReplicaCount: 1
)

// Creates a passwordless IAM database user for the service account.
service.link(database)
```

#### Firestore

This component creates a stage-scoped named Firestore database and its declared
composite indexes. Pass `databaseID: "(default)"` only when the project-global
default database is intentionally shared across stages.

```swift
let documents = GCP.FirestoreDatabase(
    "documents",
    indexes: [
        .init(
            collection: "events",
            fields: [.ascending("tenantID"), .descending("createdAt")]
        )
    ]
)

service.link(documents)
```

#### Spanner

These components create a regional or multi-region Spanner instance and a
database with an optional initial schema.

```swift
let instance = GCP.Spanner.Instance(
    "global-data",
    capacity: .autoscaling(.init())
)

let database = GCP.Spanner.Database(
    "accounts",
    instance: instance,
    schema: [
        "CREATE TABLE Accounts (AccountId STRING(36) NOT NULL) "
            + "PRIMARY KEY (AccountId)"
    ]
)

service.link(database)
```

#### Cache

This component creates a Memorystore for Redis instance on a VPC.

```swift
let cache = GCP.Cache(
    "session-cache",
    vpc: vpc,
    tier: .highAvailability,
    memorySizeGB: 2
)

service.link(cache)
```

#### Secret Manager

This component manages Secret Manager metadata and IAM access. Secret payload
versions are populated outside Swift Cloud so plaintext values are not written
to generated Pulumi YAML.

```swift
let apiKey = GCP.Secret("api-key")

let service = GCP.CloudRunService(
    "backend",
    image: image.reference,
    serviceAccount: runtimeIdentity,
    secretEnvironment: [
        .init("API_KEY", secret: apiKey.secretID)
    ]
).link(apiKey)
```

#### VPC

This component creates a custom-mode VPC, a regional subnet, and private
service access for resources such as Cloud SQL and Memorystore.

```swift
let vpc = GCP.VPC(
    "main",
    subnetCIDR: "10.0.0.0/20",
    privateServicePrefixLength: 16
)
```

#### Firewall Rule

This resource creates an ingress or egress VPC firewall rule with an explicit
allow or deny action.

```swift
let firewall = GCP.FirewallRule(
    "allow-health-checks",
    vpc: vpc,
    action: .allow([.tcp(["8080"])]),
    sourceRanges: ["35.191.0.0/16", "130.211.0.0/22"]
)
```

#### NAT Gateway

This component creates Cloud NAT for outbound internet access from private
subnets.

```swift
let nat = GCP.NATGateway(
    "outbound",
    vpc: vpc,
    logging: .errorsOnly
)
```

#### HTTPS Load Balancer

This component places a global HTTPS load balancer, managed certificate, and
DNS record in front of one Cloud Run service. The Cloud DNS zone must already
exist, and the service must use `internalLoadBalancer` ingress so its `run.app`
hostname cannot bypass the edge policy.

```swift
let edgeService = GCP.CloudRunService(
    "edge-backend",
    image: image.reference,
    serviceAccount: runtimeIdentity,
    ingress: .internalLoadBalancer
)

// "example-zone" is the existing Google-managed zone name.
let dns = GCP.DNS("example-zone", zoneName: "example.com")

let loadBalancer = GCP.HTTPSLoadBalancer(
    "backend-edge",
    service: edgeService,
    domainName: .init(hostname: "api.example.com", dns: dns),
    cdn: .enabled()
)
```

#### CDN

This component creates a global HTTPS load balancer and Cloud CDN distribution
with path-based Cloud Run, Cloud Storage, or external origins.

```swift
let assets = GCP.Bucket("assets", publicReadAccess: true)

let cdn = GCP.CDN(
    "application-edge",
    origins: [
        .cloudRun(edgeService, path: "*"),
        .bucket(assets, path: "/assets/*"),
        .external(hostname: "images.example.net", path: "/images/*"),
    ],
    domainName: .init(hostname: "www.example.com", dns: dns)
)
```

Google Cloud resource names must start with a lowercase letter, so Swift Cloud
prefixes stages such as `123-fix-login` with `s-` when generating physical
names, and hashes overlong names within each Google Cloud service's limit.
Cloud Run owns the `PORT` environment variable; the `port:` argument
configures the container port without setting that variable. Serverless network
endpoint groups are created in the region of the Cloud Run service they front,
including when it differs from the project's default region.

#### GCP coverage boundaries

The supported GCP surface covers the existing AWS provider's infrastructure
categories, but it does not pretend that unlike services have identical APIs.

| AWS surface | GCP surface | Coverage |
| --- | --- | --- |
| Web server, cluster, auto scaling | Cloud Run service and worker pool | Supported |
| Lambda and cron | Cloud Run job and Cloud Scheduler | Container workloads supported; no native Swift Cloud Functions runtime |
| API Gateway routes | API Gateway OpenAPI or gRPC document | Supported with GCP-native configuration |
| SQS queue | Cloud Tasks queue | Supported for HTTP task dispatch; applications create individual tasks |
| SNS and event sources | Pub/Sub and Eventarc | Supported |
| DynamoDB and DSQL | Firestore and Spanner | Supported through GCP-native data models |
| RDS | Cloud SQL | Supported |
| ElastiCache | Memorystore for Redis | Supported |
| CloudFront origins | Cloud CDN with Cloud Run, Storage, or external origins | Supported |
| VPC, security groups, NAT | VPC, firewall rules, and Cloud NAT | Supported |
| S3 Express One Zone | Rapid Bucket | Blocked by missing Rapid placement fields in the Pulumi GCP bucket schema |

Cloud Storage origins must be explicitly created with `publicReadAccess: true`
when used with the current CDN component. Cloud Run functions are intentionally
not modeled because Google does not offer a native Swift functions runtime;
deploy a Swift container as a Cloud Run service or job instead.

### Linking

You can link resources together to provide the necessary permissions to access
each other. This is more secure than sharing access key ids and secrets in
environment variables.

For example, you can link an S3 bucket to a Lambda function or GCP resources to
a Cloud Run service:

```swift
myFunction.link(bucket)
cloudRunService.link([bucket, secret, database, cache, topic])
```

Linking grants provider-native permissions and injects stable environment
metadata without sharing access keys.

#### Using linked resources

You can use linked resources in your server or function via environment
variables in your application:

```swift
let bucketUrl = ProcessInfo.processInfo.environment["BUCKET_MEDIA_URL"]
```

Here is a list of all the linked resources:

| Resource            | Environment Variable         |
| ------------------- | ---------------------------- |
| AWS S3 Bucket       | `BUCKET_<NAME>_URL`          |
| AWS S3 Bucket       | `BUCKET_<NAME>_HOSTNAME`     |
| AWS S3 Bucket       | `BUCKET_<NAME>_NAME`         |
| AWS SQS Queue       | `QUEUE_<NAME>_URL`           |
| AWS SQS Queue       | `QUEUE_<NAME>_NAME`          |
| AWS Lambda Function | `FUNCTION_<NAME>_URL`        |
| AWS Lambda Function | `FUNCTION_<NAME>_NAME`       |
| AWS DynamoDB Table  | `DYNAMODB_<NAME>_NAME`       |
| AWS Cache           | `CACHE_<NAME>_HOSTNAME`      |
| AWS Cache           | `CACHE_<NAME>_PORT`          |
| AWS Cache           | `CACHE_<NAME>_URL`           |
| AWS SQL Database    | `SQLDB_<NAME>_HOSTNAME`      |
| AWS SQL Database    | `SQLDB_<NAME>_PORT`          |
| AWS SQL Database    | `SQLDB_<NAME>_DATABASE_NAME` |
| AWS SQL Database    | `SQLDB_<NAME>_USERNAME`      |
| AWS SQL Database    | `SQLDB_<NAME>_PASSWORD`      |
| AWS SQL Database    | `SQLDB_<NAME>_URL`           |
| GCP Cloud Storage   | `BUCKET_<NAME>_NAME`         |
| GCP Cloud Storage   | `BUCKET_<NAME>_URL`          |
| GCP Secret Manager  | `SECRET_<NAME>_NAME`         |
| GCP Pub/Sub Topic   | `TOPIC_<NAME>_NAME`          |
| GCP Pub/Sub Topic   | `TOPIC_<NAME>_ID`            |
| GCP Subscription    | `SUBSCRIPTION_<NAME>_NAME`   |
| GCP Cloud Tasks     | `QUEUE_<NAME>_NAME`          |
| GCP Cloud Tasks     | `QUEUE_<NAME>_ID`            |
| GCP Cloud SQL       | `SQLDB_<NAME>_CONNECTION_NAME` |
| GCP Cloud SQL       | `SQLDB_<NAME>_DATABASE_NAME` |
| GCP Firestore       | `FIRESTORE_<NAME>_NAME`      |
| GCP Firestore       | `FIRESTORE_<NAME>_PROJECT_ID` |
| GCP Spanner         | `SPANNER_<NAME>_NAME`        |
| GCP Spanner         | `SPANNER_<NAME>_INSTANCE`    |
| GCP Spanner         | `SPANNER_<NAME>_PROJECT_ID`  |
| GCP Memorystore     | `CACHE_<NAME>_HOSTNAME`      |
| GCP Memorystore     | `CACHE_<NAME>_PORT`          |
| GCP Memorystore     | `CACHE_<NAME>_URL`           |
