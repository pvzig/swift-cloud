# GCP Provider Support

## Purpose

Add a first-class Google Cloud provider to Swift Cloud using the same module,
provider, resource, component, and Pulumi YAML patterns as the existing cloud
providers. Flock is the reference workload: a Swift gRPC service on Cloud Run
that publishes to Pub/Sub, connects to Cloud SQL, and may run an observability
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
- Add focused Swift Testing coverage for generated Pulumi resource shapes and
  provider configuration.
- Document a GCP project example based on Flock's Cloud Run, Pub/Sub, and Cloud
  SQL topology.

## Design boundaries

- GCP remains explicit. Provider-specific IAM, Cloud Run, Pub/Sub, and Cloud
  SQL semantics are not hidden behind provider-neutral protocols.
- API activation is explicit through `GCP.ProjectService`; components do not
  create duplicate owners for the same Google API.
- Artifact Registry authentication uses Docker's configured credential store.
  Operators run `gcloud auth configure-docker REGION-docker.pkg.dev` before a
  deployment that pushes an image.
- The first slice does not generate Cloud Endpoints/ESPv2 configuration, create
  application secrets, or encode Flock's application-specific Pulumi policy.
  Those can compose from raw resources or become later components when their
  contracts are proven independently.
- Cloud SQL creates the instance and logical database, but not a password-based
  database user. Password material requires an explicit secret-input contract
  that Swift Cloud does not currently expose.
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
  toolchain: 18 tests in 8 suites passed.
- Ran `git diff --check` and inspected the final worktree.

## Status

Implementation and local validation are complete on the `gcp-support` branch.
A live GCP preview or deployment remains an operator-owned validation step.
