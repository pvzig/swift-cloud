# GCP Provider Support

## Purpose

Add a first-class Google Cloud provider to Swift Cloud using the same module,
provider, resource, component, and Pulumi YAML patterns as the existing cloud
providers. The reference workload is a Swift gRPC service on Cloud Run that
publishes to Pub/Sub, connects to Cloud SQL, and may run an observability
sidecar. The provider should cover the infrastructure categories exposed by the
AWS module wherever Google Cloud and the Pulumi GCP provider expose an honest
equivalent.

## Scope

- Export a `CloudGCP` SwiftPM product from the umbrella `Cloud` product.
- Configure the Pulumi GCP provider with a project and region through
  `GCPProject`.
- Support explicit Google API activation so one project can declare its API
  ownership once without duplicate service resources.
- Support service accounts, project IAM roles, service-account IAM roles, and
  service identities.
- Build and push Swift service images to Artifact Registry using the existing
  Swift build/Dockerfile pipeline and the Pulumi Docker Build provider.
- Deploy Cloud Run v2 services with:
  - HTTP/1 or h2c container ports;
  - service accounts and authenticated or public invocation;
  - minimum/maximum instance scaling and request concurrency;
  - request-only or always-allocated CPU;
  - prebuilt sidecars, startup/liveness probes, and startup ordering;
  - literal and Secret Manager environment values; and
  - Cloud SQL and Secret Manager volumes.
- Support Pub/Sub topics, IAM publisher grants, pull or authenticated push
  subscriptions, retry policy, and dead-letter policy.
- Support PostgreSQL and MySQL Cloud SQL instances and logical databases.
- Store Swift Cloud passphrases and stack snapshots in a project-owned Cloud
  Storage bucket by default.
- Support GCP-native resource linking that grants the runtime service account
  least-privilege access and injects stable environment metadata.
- Support Cloud Storage buckets, Secret Manager metadata, Cloud Scheduler HTTP
  jobs, VPCs, private service networking, and Memorystore for Redis.
- Extend Cloud SQL with private IP, regional availability, IAM database users,
  and read replicas.
- Support Cloud DNS and a managed global HTTPS load balancer with optional CDN
  caching in front of Cloud Run.
- Support Cloud Run jobs and worker pools, including VPC access, secrets,
  resource links, authenticated execution, and scheduled job execution.
- Support API Gateway deployments from OpenAPI or gRPC documents, including
  the API Gateway service identity and authenticated Cloud Run backends.
- Support Eventarc triggers and Cloud Tasks queues with destination IAM,
  delivery/retry controls, and queue-scoped enqueuer access.
- Support Firestore databases and composite indexes, plus Spanner instances,
  autoscaling, databases, initial schemas, database IAM, and resource links.
- Support VPC firewall rules and Cloud NAT.
- Support multi-origin Cloud CDN distributions backed by Cloud Run, Cloud
  Storage, or external internet endpoints.
- Support Pulumi invokes for existing GCP projects, networks, subnetworks, and
  Cloud DNS managed zones.
- Add focused Swift Testing coverage for generated Pulumi resource shapes and
  provider configuration, including a complete deployment-graph fixture.
- Document the GCP surface in the README using the same component-by-component
  descriptions and focused Swift examples as the AWS surface.

## Design boundaries

- GCP remains explicit. Provider-specific IAM, Cloud Run, Pub/Sub, and Cloud
  SQL semantics are not hidden behind provider-neutral protocols.
- API activation is explicit through `GCP.ProjectService`; components do not
  create duplicate owners for the same Google API. The same rule applies to
  every other project-scoped resource: service agents come from
  `GCP.ServiceIdentity.shared`, project role bindings from
  `GCP.ServiceAccount.projectRole`, and service-account role bindings from
  `GCP.ServiceAccount.serviceAccountRole`, so components never declare
  competing owners for one IAM binding or one service agent.
- Google Cloud names must match `[a-z]([-a-z0-9]*[a-z0-9])?`. Stages default to
  the current git branch, so `Context.gcpStage` prefixes stages that do not
  begin with a letter rather than emitting names Google rejects.
- Cloud Run owns the `PORT` environment variable and rejects deployments that
  set it, so the component configures `containerPort` only.
- Serverless network endpoint groups must be co-located with their Cloud Run
  service, so the edge components read the service's own location instead of
  assuming the project default region.
- API Gateway configurations are immutable. The config id embeds a digest of
  the document and backend service-account identity so either change creates a
  new config and repoints the gateway instead of recreating an in-use id.
- Container images provide Pulumi an inline Dockerfile and opt out of image
  builds during previews. Deployments still build the release binary before
  Pulumi builds and pushes the image.
- Cloud Run secret environment names must be unique after normalization so the
  generated service, job, worker pool, or sidecar never contains duplicate
  environment-variable entries. Literal environment keys are normalized once.
- GCP linking is provider-specific because Google IAM grants roles on projects
  and individual resources rather than accepting AWS-style inline policies.
  Native links return their concrete IAM grants and add them as workload
  dependencies so Cloud Run cannot race the authorization it needs at startup.
- Provider-facing physical names apply each resource's length limit after all
  stage and component suffixes are included; Memorystore uses 40 characters and
  Compute resources use 63.
- Firestore creates a stage-scoped named database by default. The project-global
  `(default)` database remains available only through an explicit `databaseID`.
- Infrastructure-managed Pub/Sub subscriptions never expire unless callers opt
  into an inactivity duration. All protobuf duration strings preserve
  fractional seconds rather than truncating to whole seconds.
- Eventarc custom transport topics are accepted only for Pub/Sub
  `messagePublished` triggers, matching the Google API contract.
- Cloud CDN policies include an explicit signed-URL cache age so the Pulumi
  provider accepts the policy block.
- Artifact Registry authentication uses Docker's configured credential store.
  Operators run `gcloud auth configure-docker REGION-docker.pkg.dev` before a
  deployment that pushes an image.
- API Gateway is document-driven on GCP. It accepts OpenAPI or gRPC service
  configuration rather than copying the AWS route-builder API.
- Cloud Tasks is an HTTP task queue, not a subscription abstraction. The
  component owns queue policy and target authentication; applications still
  create each task and its request payload through the Cloud Tasks API.
- Firestore and Spanner cover the document and globally distributed relational
  data categories, but intentionally expose their native schemas rather than
  imitating DynamoDB or DSQL types.
- The provider does not create secret payload versions or encode
  application-specific Pulumi policy. Those require explicit secret-input and
  policy contracts.
- Secret Manager support owns metadata and IAM only. Secret payloads and
  password-based database users require an explicit secret-input contract that
  Swift Cloud does not currently expose. Cloud SQL supports passwordless IAM
  service-account users instead.
- The GCS home provider shells out through Swift Cloud's existing subprocess
  boundary to the authenticated `gcloud storage` CLI. It does not add a second
  GCP authentication implementation to the framework.
- There is no native Swift runtime for Cloud Run functions. Swift functions
  should be deployed as containerized Cloud Run services or jobs, so a
  `GCP.Function` facade would misrepresent the deployment model.
- Google Cloud supports Rapid Bucket, but Pulumi GCP `Bucket` does not expose
  the placement fields required to configure it. Express/Rapid bucket parity is
  deferred until those fields exist in the provider schema.
- Cloud Storage CDN origins require `publicReadAccess: true` with the current
  backend-bucket design. Private signed-origin access is a separate contract.
- No live GCP deployment is part of local validation because it would mutate a
  user's cloud project and incur cost.

## Dependency versions

- Pulumi GCP provider `9.33.0`, verified as the latest GitHub release on
  2026-08-05.
- Pulumi Docker Build provider `0.0.22`, verified as the latest GitHub release
  on 2026-08-05.

## AWS-to-GCP coverage

| AWS category | GCP implementation | Status |
| --- | --- | --- |
| WebServer, Cluster, AutoScaling | CloudRunService, CloudRunWorkerPool | Covered |
| Function, Cron | CloudRunJob, SchedulerJob | Container equivalent; native functions are a platform gap |
| APIGateway | APIGateway | Covered with OpenAPI/gRPC configuration |
| Queue | TaskQueue | Covered with GCP-native HTTP dispatch semantics |
| Topic and event sources | Topic, Subscription, EventarcTrigger | Covered |
| DynamoDB, DSQL | FirestoreDatabase, Spanner.Instance/Database | Covered with GCP-native schemas |
| SQLDatabase | SQLDatabase | Covered |
| Cache | Cache | Covered for Redis |
| Bucket | Bucket | Covered |
| CDN | CDN, HTTPSLoadBalancer | Covered for Cloud Run, Storage, and external origins |
| VPC, SecurityGroup, NAT | VPC, FirewallRule, NATGateway | Covered |
| ExpressBucket | Rapid Bucket | Pulumi provider surface gap |
| Resource lookups | Project, network, subnetwork, DNS invokes | Covered |

## Validation

- Formatted all changed Swift sources with `swift-format`.
- Built all package products with the Swift 6.3.3 release toolchain.
- Ran the complete test suite with Swift 6.3.3: 58 tests in 18 suites passed.
- Encoded a production deployment fixture containing more than 90 resources
  and verified that every Pulumi logical name is unique.
- Exercised GCS home bootstrap and JSON round trips through an injected,
  in-memory `gcloud` command boundary; no live cloud calls were made.
- Ran `git diff --check` and inspected the final worktree.
- Reviewed every GCP component example in the README against its public Swift
  initializer and the complete deployment-graph fixture.

## Status

The GCP implementation covers the existing AWS infrastructure categories where
Google Cloud and Pulumi expose a real equivalent. Native Swift functions and
Rapid Bucket remain documented platform/provider boundaries. A live GCP preview
or deployment remains an operator-owned validation step.
