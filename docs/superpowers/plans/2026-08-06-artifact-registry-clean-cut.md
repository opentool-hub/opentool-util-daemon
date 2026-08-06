# Artifact Registry Clean-Cut Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the unreleased compatibility bridge with one canonical Artifact Registry implementation shared by the daemon and AgentOS Embedded.

**Architecture:** The daemon persists canonical Artifact, Server, Tool, operation, schema, builtin bundle, and API-key records directly, with every Server mutation passing through `ArtifactRegistryService`. HTTP/Dart APIs expose only Pull/Register and immutable Server terminology. AgentOS Embedded requires that contract and contains no legacy mode or legacy DTO fallback.

**Tech Stack:** Dart 3, Shelf, Hive, json_serializable, archive/path, Dart test; AgentOS Embedded Dart/Shelf plus TypeScript/Vitest.

## Global Constraints

- Existing development databases do not need migration and may be deleted manually.
- Do not modify unrelated dirty-worktree files or bundled binaries.
- Keep `apiVersion: 2`, `artifactRegistryV2`, `builtinReconcileV1`, `pullSseV1`, and `toolMaterializationV1`.
- Keep strict ZIP traversal, duplicate-entry, link, special-file, entry-count, and expanded-size validation.
- All new behavior must follow a witnessed red-green TDD cycle.
- Generated Dart files are regenerated with build_runner, not hand-maintained.

---

### Task 1: Windows-safe ZIP creation

**Files:**
- Modify: `test/utils/zip_util_test.dart`
- Modify: `lib/src/utils/zip_util.dart`

**Interfaces:**
- Produces: `ZipUtil.archivePath(String sourcePath, String entityPath, {p.Context? context}) -> String`, returning a safe POSIX relative archive path.

- [ ] **Step 1: Write the failing test**

Add a test using `p.Context(style: p.Style.windows)` that passes `C:\\src\\tool` and `C:\\src\\tool\\bin\\demo.exe` and expects `bin/demo.exe`. Add an integration assertion that `zipDirectory` produces only `/`-separated entry names.

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/utils/zip_util_test.dart`
Expected: FAIL because Windows relative paths remain backslash-separated or the helper is absent.

- [ ] **Step 3: Implement minimal path canonicalization**

Calculate the relative path with the supplied/native context, split it with that context, and join components with `p.posix.joinAll`. Use this helper in `zipDirectory` before constructing `ArchiveFile`.

- [ ] **Step 4: Run focused test**

Run: `dart test test/utils/zip_util_test.dart`
Expected: PASS.

### Task 2: Family-scoped builtin rollback and recovery

**Files:**
- Modify: `test/service/artifact_registry_service_test.dart`
- Modify: `lib/src/service/builtin_reconcile_service.dart`

**Interfaces:**
- Produces: builtin operation payload containing `bundleFamily`, `desiredBundleId`, `familyServers`, `createdServerIds`, and `previousBundle`.
- Preserves: unrelated Server rows on synchronous rollback and startup recovery.

- [ ] **Step 1: Write failing rollback tests**

Inject a storage failure after the builtin snapshot, add an unrelated Hub Server, and assert the unrelated row survives rollback. Add a recovery test with the same operation payload and unrelated row.

- [ ] **Step 2: Run tests to verify both fail**

Run: `dart test test/service/artifact_registry_service_test.dart -n 'builtin reconcile'`
Expected: FAIL because current rollback removes every Server outside the global snapshot.

- [ ] **Step 3: Implement family-scoped state**

Snapshot only builtin rows in the requested family. Track IDs created by this reconcile in the durable payload as they are created. Rollback/recovery remove only tracked IDs and restore only captured family rows; do not touch other source kinds or bundle families.

- [ ] **Step 4: Run focused tests**

Run: `dart test test/service/artifact_registry_service_test.dart -n 'builtin reconcile'`
Expected: PASS.

### Task 3: Materialization digest rollback

**Files:**
- Modify: `test/service/artifact_registry_service_test.dart`
- Modify: `lib/src/service/tool_materialization_service.dart`

**Interfaces:**
- Operation payload adds `previousDigest`.
- Rollback restores both previous workspace and previous Tool digest.

- [ ] **Step 1: Write a failing storage-fault test**

Use a controllable operation storage that throws while persisting the stage immediately after `tools.update`. Assert the previous workspace content and previous digest are both restored and extraction/staging leftovers are removed.

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/service/artifact_registry_service_test.dart -n 'materialization'`
Expected: FAIL because the digest remains the new value after workspace rollback.

- [ ] **Step 3: Implement symmetric rollback and cleanup**

Persist `previousDigest`, retain the extraction path for `finally` cleanup, and restore the Tool row before removing the operation. Make recovery validate the workspace manifest and use recorded digests/stages to commit or roll back.

- [ ] **Step 4: Run focused tests**

Run: `dart test test/service/artifact_registry_service_test.dart -n 'materialization'`
Expected: PASS.

### Task 4: Canonical Pull and exception vocabulary

**Files:**
- Modify: `test/service/artifact_downloader_test.dart`
- Modify: `test/utils/platform_detector_test.dart`
- Replace tests: `test/service/hub_install_service_test.dart`, `test/service/hub_install_acceptance_test.dart`
- Modify: `test/controller/server_controller_test.dart`
- Modify: `lib/src/service/artifact_downloader.dart`
- Modify: `lib/src/utils/platform_detector.dart`
- Modify: `lib/src/service/exception.dart`
- Replace: `lib/src/service/hub_pull_service.dart`
- Delete: `lib/src/service/hub_install_service.dart`
- Modify: `lib/src/service/server_service.dart`
- Modify: `lib/src/controller/server_controller.dart`

**Interfaces:**
- Produces only `HubPullRequest`, `PullEvent`, `HubPullService.pull`, `ArtifactOperationException`, and `ServerService.registerHubArtifact`.

- [ ] **Step 1: Convert tests to canonical symbols and stages**

Rename Hub install tests and expectations to Pull terminology, require `registering`/`ready`, and expect `ArtifactOperationException` codes.

- [ ] **Step 2: Run focused tests to verify compile/test failure**

Run: `dart test test/service/artifact_downloader_test.dart test/utils/platform_detector_test.dart test/service/hub_install_service_test.dart test/service/hub_install_acceptance_test.dart test/controller/server_controller_test.dart`
Expected: FAIL while production still exposes Install compatibility types/stages.

- [ ] **Step 3: Move implementation and remove compatibility facade**

Put the canonical implementation in `hub_pull_service.dart`, rename `installHubArtifact` to `registerHubArtifact`, replace every `InstallException`, rename controller fields, and delete aliases/facades.

- [ ] **Step 4: Run focused tests**

Run the Step 2 command.
Expected: PASS.

### Task 5: Canonical persistence with no migration bridge

**Files:**
- Modify: `lib/src/storage/dao.dart`
- Regenerate: `lib/src/storage/dao.g.dart`
- Replace: `lib/src/storage/v2_storage.dart` with `lib/src/storage/registry_storage.dart`
- Delete: `lib/src/storage/hive_storage.dart`
- Delete: `lib/src/service/schema_migration_service.dart`
- Delete: `test/service/schema_migration_service_test.dart`
- Delete: `test/storage/hive_server_storage_migration_test.dart`
- Modify: `lib/src/storage/cache_storage.dart`
- Modify: `lib/src/service/server_service.dart`
- Modify: `lib/src/service/tool_service.dart`
- Modify: `lib/src/service/manage_service.dart`
- Modify: `lib/src/server.dart`
- Modify: `test/test_doubles.dart`
- Modify: daemon service/controller tests that construct legacy storage doubles.

**Interfaces:**
- Produces canonical `ArtifactDao`, `ServerDao`, `ToolDao`, `ArtifactOperationDao`, `SchemaMetaDao`, `BuiltinBundleDao`, and `RegistryStorageBundle`.
- `ServerService` requires registry-backed storage and has no nullable registry/internal storage fallback.

- [ ] **Step 1: Update storage/service tests to canonical in-memory storage**

Replace `StubHive*Storage` dependencies with generic `MemoryStorage<T>` doubles and construct `ServerService` with registry-backed dependencies only.

- [ ] **Step 2: Run daemon tests to verify compile failure**

Run: `dart test`
Expected: FAIL because canonical types and constructors do not yet exist.

- [ ] **Step 3: Implement canonical DAOs and storage bundle**

Remove legacy DAOs/adapters, rename new-schema DAOs, create direct Hive storage classes plus API-key storage in `registry_storage.dart`, and regenerate adapters with `dart run build_runner build --delete-conflicting-outputs`.

- [ ] **Step 4: Remove migration and fallback code**

Initialize `RegistryStorageBundle` directly in `DaemonServer`; make ServerService build/import/export/delete and ToolService materialization use registry storage exclusively; remove legacy recovery/tests.

- [ ] **Step 5: Run formatting and full daemon tests**

Run: `dart format lib test && dart test`
Expected: PASS.

### Task 6: Canonical HTTP/Dart Server API

**Files:**
- Modify: `test/client/server_client_test.dart`
- Modify: `test/controller/server_controller_test.dart`
- Modify: `lib/src/controller/dto.dart`
- Regenerate: `lib/src/controller/dto.g.dart`
- Modify: `lib/src/client/client.dart`
- Modify: `lib/src/controller/server_controller.dart`
- Modify: `lib/src/router.dart`
- Modify: `lib/src/service/model.dart`
- Modify: `README.md`
- Modify: `README-zh_CN.md`

**Interfaces:**
- Server JSON contains canonical fields only.
- `DaemonClient.pullServer` requires `onPullError`.
- No tag endpoint or client method.

- [ ] **Step 1: Update contract tests first**

Assert Server serialization omits `repo`, `tag`, and `installedAt`, parsing requires canonical fields, Pull requires `onPullError`, and the tag route/client request is absent.

- [ ] **Step 2: Run tests to verify failure**

Run: `dart test test/client/server_client_test.dart test/controller/server_controller_test.dart`
Expected: FAIL against compatibility DTO/client/router behavior.

- [ ] **Step 3: Remove legacy API fields and endpoint**

Update models/DTOs/client/controller/router, regenerate JSON code, and make Pull done events serialize `OpenToolServerDto` rather than a separate legacy-shaped map.

- [ ] **Step 4: Update public documentation and run focused tests**

Correct loopback documentation and remove tag/migration/install terminology. Run the Step 2 command and expect PASS.

### Task 7: AgentOS Embedded canonical daemon contract

**Files:**
- Modify: `/Users/shui/WebstormProjects/agentos/agentos_embedded/lib/src/server/services/opentool_daemon_capabilities.dart`
- Modify: `/Users/shui/WebstormProjects/agentos/agentos_embedded/lib/src/server/services/opentool_builtin_sync.dart`
- Modify: `/Users/shui/WebstormProjects/agentos/agentos_embedded/lib/src/server/controllers/opentool_hub_controller.dart`
- Modify: `/Users/shui/WebstormProjects/agentos/agentos_embedded/test/opentool_daemon_capabilities_test.dart`
- Modify: `/Users/shui/WebstormProjects/agentos/agentos_embedded/test/opentool_hub_test.dart`
- Modify: `/Users/shui/WebstormProjects/agentos/agentos_embedded/webshell-host/plugins/opentool/src/types.ts`
- Modify: `/Users/shui/WebstormProjects/agentos/agentos_embedded/webshell-host/plugins/opentool/src/types.test.ts`
- Modify only directly affected OpenTool docs/config text.

**Interfaces:**
- Daemon mode is `ready`, `incompatible`, or `down`; no legacy execution path.
- Server parser accepts canonical fields only.

- [ ] **Step 1: Update Embedded tests to reject legacy payloads/fallbacks**

Require `apiVersion >= 2` plus `artifactRegistryV2`, assert old Server field-only payloads are rejected/empty rather than normalized, and remove expectations around legacy builtin sync.

- [ ] **Step 2: Run focused Dart and web tests to verify failure**

Run Dart: `dart test test/opentool_daemon_capabilities_test.dart test/opentool_hub_test.dart`
Run web from `webshell-host`: `npm test -- --run plugins/opentool/src/types.test.ts plugins/opentool/src/api-runtime.test.ts`
Expected: FAIL while legacy mode and parser fallbacks remain.

- [ ] **Step 3: Remove legacy Embedded branches and parser fallback**

Collapse capability handling to ready/incompatible/down, always use V2 builtin reconcile, remove migration marker/state fallback, and parse only namespace/version/createdAt.

- [ ] **Step 4: Run focused tests**

Run both Step 2 commands.
Expected: PASS.

### Task 8: Final regeneration, verification, and review

**Files:**
- Modify generated files only through build_runner/formatters.
- Review all touched files in both repositories.

- [ ] **Step 1: Scan for forbidden compatibility symbols**

Run daemon scan: `rg -n "SchemaMigrationService|HubInstall|InstallException|onInstallError|installedAt|tagServer|/<serverId>/tag|HiveServerStorage|HiveToolStorage|InternalServerDao" lib test README.md README-zh_CN.md`
Expected: no OpenTool compatibility matches.

Run Embedded scan for `OpentoolDaemonMode.legacy`, Server `repo/tag/installedAt` fallbacks, and builtin migration markers; unrelated application/plugin `installedAt` fields are ignored.

- [ ] **Step 2: Verify daemon**

Run: `dart format --output=none --set-exit-if-changed lib test && dart analyze && dart test && git diff --check`
Expected: every command exits 0.

- [ ] **Step 3: Verify AgentOS Embedded**

Run the focused Dart and web tests from Task 7, then `dart analyze` in `agentos_embedded` if its current dirty worktree has no unrelated analyzer blockers.
Expected: focused commands exit 0; any unrelated pre-existing analyzer failure is reported separately with evidence.

- [ ] **Step 4: Inspect scope**

Review `git status --short` and `git diff --stat` in both repositories. Confirm no bundled binaries, vendor submodules, or unrelated UI files were changed by this implementation.

