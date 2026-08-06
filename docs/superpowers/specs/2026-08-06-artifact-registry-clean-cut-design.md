# Artifact Registry Clean-Cut Design

## Context

OpenTool daemon 0.4.0 and the matching `agentos_embedded` integration are still
under development and have not been released. Development data may be deleted;
there is no requirement to read, migrate, or downgrade to the earlier Hive
schema or HTTP/Dart API.

The implementation therefore adopts the new Artifact → Server reference → Tool
materialization model as the only supported design instead of carrying a V1/V2
compatibility bridge.

## Goals

- Make the content-addressed Artifact Registry the only path that writes or
  removes Server and Tool persistence.
- Expose only Pull/Register terminology and the canonical V2 HTTP payload.
- Remove unused migration, legacy storage, legacy tag mutation, and Install
  compatibility APIs.
- Make ZIP creation portable on Windows while retaining strict extraction
  validation.
- Make builtin reconcile rollback unable to remove unrelated concurrent Server
  registrations.
- Keep Tool workspace content and `materializedArtifactDigest` consistent when
  materialization fails or is recovered after interruption.
- Update `agentos_embedded` to require the canonical daemon contract without
  legacy negotiation or legacy DTO fallbacks.

## Non-goals

- Migrating existing `.opentool/db` data.
- Supporting downgrade to daemon 0.3.x.
- Preserving `HubInstall*`, `InstallException`, `onInstallError`, Server tag
  mutation, or `repo`/`tag`/`installedAt` DTO fields.
- Refactoring unrelated AgentOS Embedded UI or application installation code.

## Canonical Storage Architecture

The daemon initializes one storage bundle containing Artifact, Server, Tool,
operation, schema metadata, builtin bundle, and API-key boxes. The existing
content-addressed box versions such as `artifacts_v1` remain because they are
the first versions of the new schema and provide a future upgrade boundary;
they do not imply compatibility with the old daemon.

Canonical persistent types are named `ArtifactDao`, `ServerDao`, `ToolDao`,
`ArtifactOperationDao`, `SchemaMetaDao`, and `BuiltinBundleDao`. Old
`InternalServerDao`, V1 Server/Tool adapters, `Hive*Storage` compatibility
implementations, V2 adapter bridges, and `SchemaMigrationService` are removed.

`ServerService` receives canonical Server and Tool storage plus an
`ArtifactRegistryService`. Build, import, Hub pull, builtin reconcile, delete,
export, and Tool materialization always use this registry-backed model; there
is no nullable registry or legacy fallback branch.

Development environments must delete the old `.opentool/db` before starting
the new daemon. Startup must fail clearly on incompatible existing boxes rather
than attempting implicit migration.

## Canonical API

The daemon keeps `/version` with `apiVersion: 2` and capability negotiation as
the shared contract currently consumed by AgentOS Embedded. This is a contract
identifier for the coordinated development stack, not a promise to support the
unreleased legacy implementation.

Server payloads contain only canonical fields:

- `id`, `alias`, `namespace`, `name`, `version`
- `source`, `platform`, `size`, `createdAt`
- `artifact`, `policy`, `capabilities`, `state`, `schemaVersion`

The daemon and Dart client remove `repo`, `tag`, and `installedAt`. The
`/servers/{serverId}/tag` endpoint and `DaemonClient.tagServer` are removed.
Versions are immutable source identity; a different version must be registered
as a different Server reference.

Hub distribution uses `HubPullRequest`, `PullEvent`, `HubPullService`,
`ArtifactOperationException`, `registerHubArtifact`, and `onPullError` only.
SSE stages are `resolving`, `downloading`, `verifying`, `registering`, and
`ready` only.

AgentOS Embedded treats any daemon without `apiVersion >= 2` and
`artifactRegistryV2` as unavailable/incompatible. It removes legacy builtin
sync, migration markers, legacy mode, and DTO fallbacks to `repo`, `tag`, or
`installedAt`.

## Windows-safe ZIP Handling

ZIP creation converts every platform-relative filesystem path into a POSIX
archive path before creating `ArchiveFile`. The validator continues to reject
backslashes, absolute paths, traversal, duplicates, links, and special files.
Tests use `package:path/path.dart` Windows context to prove that a Windows
relative path is encoded with `/`, and they inspect the resulting archive using
the production validator.

## Builtin Reconcile Atomicity

Builtin reconcile must never snapshot and restore the entire Server table.
Before mutation it records only:

- Server rows whose `sourceKind` is `builtin` and whose
  `builtinBundleFamily` matches the requested family.
- The previous `BuiltinBundleDao` for that family.
- IDs created by the current reconcile operation.

Rollback removes only rows created by that reconcile and restores only the
captured family rows. Hub, import, build, and other builtin-family rows created
concurrently are left untouched. Recovery uses the same family-scoped payload.
The registry remains authoritative for Artifact garbage collection after the
family-scoped rollback.

## Tool Materialization Atomicity

Materialization captures the Tool's prior digest in the durable operation
payload before changing the workspace. On failure after the Tool row is
updated, rollback restores both the previous workspace and previous digest.
Recovery decides between commit and rollback using the operation stage,
workspace manifest, current Tool digest, and recorded previous digest.

Temporary extraction directories, staging directories, and previous workspace
directories are removed on every success and failure path. A failure to persist
an operation stage must not leave the Tool row describing different content
from the restored workspace.

## Error Handling

All artifact, pull, platform-detection, registration, storage-policy, and
materialization failures use `ArtifactOperationException` with a stable code,
retryability, and optional request ID. HTTP mapping continues to return stable
JSON error envelopes.

Startup and storage initialization errors are fatal and identify incompatible
development storage. No automatic destructive cleanup is performed by daemon
startup.

## Testing

The implementation follows red-green-refactor cycles and adds regression tests
for:

- Windows archive path canonicalization.
- Builtin reconcile failure and recovery while an unrelated Server is added
  after the snapshot.
- Tool materialization failure after the Tool digest update.
- Absence of tag routes/client methods and legacy Pull/Install symbols.
- Canonical Server JSON parsing without legacy fields.
- AgentOS Embedded rejecting non-V2 daemons and parsing only canonical Server
  fields.

Verification runs daemon formatting, analysis, full Dart tests, and diff
checks. AgentOS Embedded verification runs its focused Dart tests and the
OpenTool web plugin tests affected by parser/contract changes, followed by its
available analyzer/build checks.

## Documentation

README and architecture documentation describe only the canonical contract,
remove migration and compatibility language, remove the tag endpoint, and state
that the repository config binds `127.0.0.1`.

