## 0.5.3

- Upgrade the OpenTool Dart SDK to 3.0.0 for complete JSON Schema support
- Require Dart SDK 3.13 or later

## 0.5.2

- Return Build SSE immediately, stream command output while it is produced, and
  finish only with a terminal `done` or structured `error` event
- Advertise `buildSseTerminalV1` so clients reject daemons that do not support
  the terminal Build stream contract
- Standardize expected validation, filesystem, authentication, and not-found
  failures as actionable 4xx error envelopes instead of generic 500 responses
- Add correlated Server build lifecycle logs with command exit codes, stdout,
  stderr, failure phases, and durations
- Return failed Server build commands as `422 BUILD_COMMAND_FAILED` with
  bounded diagnostics for CLI clients

## 0.5.1

- Record the detected platform ABI in generated `.ots` manifests and exported
  artifact filenames; legacy Linux manifests without ABI default to `glibc`
- Accept and safely materialize relative symbolic links that remain inside an
  `.ots` archive, including signed macOS framework bundles
- Continue rejecting absolute or archive-escaping symbolic-link targets

## 0.5.0

- Make terminal-ready `DONE`/`ERROR` semantics mandatory for Tool start
- Add typed, subscription-cancellable Pull events and detailed Server deletion results
- Expose stable `DaemonApiException` values instead of leaking Dio failures from the public client
- Fix `startTool` ERROR handling and make its Future wait for a terminal event

## 0.4.0

- Add V2 content-addressed Artifact, Server reference, Tool, operation, schema, and builtin bundle storage
- Route Hub pull, local import/build, and builtin reconcile through one Artifact registry
- Add crash recovery, reference-aware deletion/GC, protected builtin policy, and host-token authentication
- Add atomic Tool rematerialization with persisted artifact digest and derived content state
- Add API version/capability negotiation, V2 Server DTOs, stable domain errors, and Pull SSE stages
- Migrate V1 data copy-on-write while preserving Server IDs, aliases, Tool links, and rollback inventory
- Default daemon binding to loopback and redact request bodies, signed URLs, credentials, and local paths from logs

## 0.3.0

- Replace daemon-side Hub login and push with anonymous resolve/download/install
- Verify artifact size and SHA-256 before atomic installation
- Persist Hub source, immutable version/artifact digests, platform, size, media type, and installation time
- Add exact-version pull SSE events and stable install errors
- Treat premature pull stream closure as failure and allow loopback HTTP registries for local development
- Migrate local server identity from `native/native` to `local/local`
- Honor explicit `--config` files and support partial configuration overrides
- Preserve artifact metadata when assigning additional tags to local servers
- Add cross-platform Hub install, restart, rollback, interrupted-download, and proxy-error acceptance coverage

## 0.2.2

- add server metadata to tool list responses

## 0.2.1

- Add `/tools/events` SSE subscription for tool lifecycle changes
- Emit `tool.draining` before stop/delete and `tool.ready` only after readiness checks pass
- Extend the Dart client and docs for tool lifecycle SSE subscriptions

## 0.2.0

- Support OpenTool Spec 2.0, add stream Call
- separate server and tool

## 0.1.0

- Initial version.
