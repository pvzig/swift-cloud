# GCP Provider Support

## Purpose

Add a first-class Google Cloud provider to Swift Cloud using the same module,
provider, resource, component, and Pulumi YAML patterns as the existing cloud
providers. The reference workload is a Swift gRPC service on Cloud Run that
publishes to Pub/Sub, connects to Cloud SQL, and may run an observability
sidecar.

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
- Add focused Swift Testing coverage for generated Pulumi resource shapes and
  provider configuration, including a complete deployment-graph fixture.
- Document a GCP project example based on a production Cloud Run, Pub/Sub, and
  Cloud SQL topology.

## Design boundaries

- GCP remains explicit. Provider-specific IAM, Cloud Run, Pub/Sub, and Cloud
  SQL semantics are not hidden behind provider-neutral protocols.
- API activation is explicit through `GCP.ProjectService`; components do not
  create duplicate owners for the same Google API.
- GCP linking is provider-specific because Google IAM grants roles on projects
  and individual resources rather than accepting AWS-style inline policies.
- Artifact Registry authentication uses Docker's configured credential store.
  Operators run `gcloud auth configure-docker REGION-docker.pkg.dev` before a
  deployment that pushes an image.
- The provider does not generate Cloud Endpoints/ESPv2 configuration, create
  secret payload versions, or encode application-specific Pulumi policy.
  Those can compose from raw resources or become later components when their
  contracts are proven independently.
- Secret Manager support owns metadata and IAM only. Secret payloads and
  password-based database users require an explicit secret-input contract that
  Swift Cloud does not currently expose. Cloud SQL supports passwordless IAM
  service-account users instead.
- The GCS home provider shells out through Swift Cloud's existing subprocess
  boundary to the authenticated `gcloud storage` CLI. It does not add a second
  GCP authentication implementation to the framework.
- No live GCP deployment is part of local validation because it would mutate a
  user's cloud project and incur cost.

## Dependency versions

- Pulumi GCP provider `9.33.0`, verified as the latest GitHub release on
  2026-08-05.
- Pulumi Docker Build provider `0.0.22`, verified as the latest GitHub release
  on 2026-08-05.

## Validation

- Formatted all changed Swift sources with `swift-format`.
- Built all package products with the Swift 6.3 release toolchain.
- Ran the complete test suite in parallel with the Swift 6.3 release
  toolchain: 26 tests in 14 suites passed.
- Encoded a 46-resource production deployment fixture and verified that every
  Pulumi logical name is unique.
- Exercised GCS home bootstrap and JSON round trips through an injected,
  in-memory `gcloud` command boundary; no live cloud calls were made.
- Ran `git diff --check` and inspected the final worktree.

## Status

The broader GCP parity expansion and local validation are complete on the
`gcp-support` branch. A live GCP preview or deployment remains an
operator-owned validation step.
