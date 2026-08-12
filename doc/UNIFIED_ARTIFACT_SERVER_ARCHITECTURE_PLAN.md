# OpenTool Daemon 统一 Artifact / Server 架构实施方案

> 目标工程：`opentool-util-daemon`
>
> 配套文档：`agentos_embedded/docs/OPENTOOL_PULL_AND_MANAGEMENT_UI_PLAN.md`
>
> 更新日期：2026-08-05

## 1. 目标

OpenTool Hub 接入后，daemon 不再把 Hub 拉取、本地 `.ots` 导入、本地构建和系统内置
制品视为四套管理逻辑。四种入口最终都进入同一个本地 Artifact 仓库，并通过统一的
Server 引用运行 Tool。

```text
Hub Pull ───────────┐
Local Import ───────┤
Local Build ────────┼─→ Artifact Registry ─→ Server Reference ─→ Tool Instance
Builtin Reconcile ──┘
```

稳定原则：

> Hub 是默认分发渠道；daemon 是本地 Artifact、Server 引用和 Tool 运行状态的唯一
> 权威。Pull、Import、Build、Builtin Reconcile 只是 Artifact 进入本地仓库的不同方式。

## 2. OpenTool 术语统一

### 2.1 对外操作

| 操作 | 含义 |
| --- | --- |
| `pull` | 从 Hub resolve 并拉取精确版本，随后注册为本地 Server |
| `import` | 从本地 `.ots` 文件注册 Server |
| `build` | 从源码生成 `.ots`，随后注册 Server |
| `builtin reconcile` | 将宿主提供的系统内置清单同步到 daemon |
| `run` | 从本地 Server 创建 Tool 实例 |
| `start/stop` | 控制 Tool 实例生命周期 |

OpenTool 对外 API、CLI、SSE、错误码和文档不再使用 `Hub install`。当前工程内的 App
安装模块不属于 OpenTool 范畴，不在本次重命名范围内。

### 2.2 代码命名目标

```text
HubInstallService       → HubPullService
HubInstallRequest       → HubPullRequest
HubInstallEvent         → PullEvent
install()               → pull()
installHubArtifact()    → registerHubArtifact()
InstallException        → ArtifactOperationException
INSTALL_FAILED          → PULL_FAILED 或 REGISTER_FAILED
```

`installedAt` 不再作为 OpenTool 领域主术语；新模型统一使用 `createdAt` 或
`registeredAt`。旧 DTO 字段可保留一个兼容版本，但新客户端不得继续依赖。

## 3. 目标数据模型

### 3.1 Artifact 是不可变物理内容

新增 `ArtifactDao`，以 Artifact SHA-256 digest 为主键：

```text
ArtifactDao
  digest              sha256:...，主键
  size
  mediaType
  platformOs
  platformArch
  platformAbi
  filePath
  manifestName
  manifestVersion
  verifiedAt
  createdAt
```

Artifact 不保存单一 `source.kind`。相同内容可能同时被系统内置、本地导入和 Hub 引用，
来源属于 Server 引用，而不是物理内容。

物理文件改为内容寻址：

```text
${OPENTOOL_PATH}/content/sha256/ab/cdef0123456789....ots
```

其中目录取 digest 前两位，文件名取剩余十六进制值。同一 digest 只保存一次。

### 3.2 Server 是 Artifact 的逻辑引用

重构 `ServerDao`：

```text
ServerDao
  id
  alias
  namespace
  name
  version
  artifactDigest       → ArtifactDao.digest

  sourceKind           hub | builtin | import | build
  sourceKey            来源内稳定唯一键
  registry             Hub 可选
  versionDigest        Hub 可选
  hubArtifactId        Hub 可选
  builtinBundleId      Builtin 可选
  builtinKey           Builtin 可选

  protected
  managedBy            agentos-embedded | user | daemon
  state                available | retired | broken
  createdAt
```

约束：

- `(sourceKind, sourceKey)` 在 Server 表中唯一，`artifactDigest` 不参与来源身份计算。
- Hub `sourceKey`：`registry|namespace|name|version`。
- Builtin `sourceKey`：`bundleFamily|builtinKey`，版本和具体 `bundleId` 不参与稳定身份计算。
- Import `sourceKey`：`namespace|name|version`。相同 sourceKey 与相同 digest 幂等；digest
  不同返回 `ARTIFACT_SOURCE_CONFLICT`。
- Build `sourceKey`：`namespace|name|version`，可追加调用方显式提供的稳定 `projectKey`；不得
  使用绝对源码路径作为稳定身份。相同 sourceKey 与不同 digest 同样返回冲突。
- 相同 Artifact 可以被多个 Server 引用；不能通过复制 `.ots` 实现多引用。
- alias 不是来源身份的一部分，修改 alias 不得创建新的 Server 或 Artifact。

### 3.3 Tool 引用 Server

`ToolDao` 继续以 `serverId` 关联 Server，并追加 `materializedArtifactDigest`，表示当前 Tool
工作目录实际由哪个 Artifact 物化。该字段不是 Server 当前 digest 的普通快照，两者不一致时
必须执行明确的重物化流程，不能仅记录日志后继续运行旧目录。

Tool 与 Server 内容变更的稳定语义：

Tool 查找、Run single-flight 和复用以 `serverId` 为键，不以 namespace/name/version 或
artifact digest 代替；多个 Server 即使引用相同 Artifact 仍是不同运行来源。

1. 创建 Tool 时，将 Server Artifact 原子解包到 Tool 工作目录，并写入
   `materializedArtifactDigest`。
2. Server 更新 Artifact 时，正在运行的 Tool 不热替换，允许其继续运行到用户停止。
3. 停止状态的 Tool 再次 Run/Start 或参与 autoRestore 前，若 digest 不一致，先在临时目录
   重物化，原子替换成功后再启动。
4. 重物化保留 Tool ID、alias、API key、extra commands 和端口偏好；失败时保留旧工作目录，
   Tool 保持停止并返回明确错误。
5. `retired` Server 不创建新 Tool、不重物化、不 autoRestore；已经运行的 Tool 可以停止或删除。
6. 旧 Tool 没有 digest 时视为 `unknown`。下一次需要启动时从当前 Server 重物化，不能假定旧
   工作目录与当前 Server 一致。

迁移和 builtin 更新必须保持既有 Server ID，不能使已有 Tool 丢失关联。

## 4. 统一注册管线

新增 `ArtifactRegistryService`，所有入口只能通过该服务写 Artifact 和 Server：

```text
registerArtifact(
  artifactInput,
  serverReferenceInput,
  policy,
  expectedMetadata?
) → ServerModel
```

统一步骤：

1. 在 daemon 数据目录创建唯一 `.part`。
2. 流式计算 size 与 SHA-256。
3. 校验 ZIP 路径、重复项、特殊文件、文件数和展开大小。
4. 校验唯一根 `Opentoolfile.json`。
5. 校验名称、版本、平台、workdir 和 entrypoint。
6. 写入 digest 对应 content path；已存在相同 digest 时复用。
7. 创建或复用 `ArtifactDao`。
8. 创建 Server 引用。
9. 通知 Server 列表变化并返回完整 Server。

调用关系：

```text
HubPullService.pull()           → ArtifactRegistryService.registerArtifact()
ServerService.import()          → ArtifactRegistryService.registerArtifact()
ServerService.build()           → ArtifactRegistryService.registerArtifact()
BuiltinReconcileService.sync()  → ArtifactRegistryService.registerArtifact()
```

禁止保留第二套 Hub 专用落库或本地导入落库实现。

## 5. 持久化、原子性与恢复

保留 Hive，但增加明确的 Box：

```text
artifacts_v1
servers_v2
tools_v2
artifact_operations_v1
schema_meta_v1
builtin_bundles_v1
```

`ArtifactOperationDao` 至少包含：

```text
id
type                 pull | import | build | builtin | remove | gc | migration | materialize
stage                由 operation type 决定，见下表
tempPath
digest
serverId
createdAt
```

```text
register     created → contentWritten → artifactWritten → referenceWritten → committed
remove/gc    created → referenceRemoved → contentTrashed → artifactRemoved → committed
materialize  created → staged → previousMoved → workspaceMoved → toolUpdated → committed
migration    started → boxesWritten → verified → schemaActivated → cleanupPending → committed
```

写入顺序：

```text
创建 operation
→ 写入并校验 .part
→ 原子移动到 content path
→ 写 ArtifactDao
→ 写 ServerDao
→ 标记 committed
→ 删除 operation
```

删除、GC 和迁移同样必须写 operation 或等价 tombstone，不能只有注册流程可恢复。Hive 不提供
跨 Box 事务，operation 是恢复依据，不是审计日志。

启动恢复必须：

- 删除遗留 `.part`。
- 回滚或补全未完成 operation。
- 删除没有 Artifact 记录、没有未完成 operation 引用的孤儿内容文件。
- 物理文件缺失时保留 Server ID 和 Tool 关联，将相关 Server 标记为 `broken`；不得在普通启动
  恢复中静默删除 Server。
- 只有确认无 Server 引用、无 operation 使用时才清理 Artifact 记录和物理文件。
- 不删除仍被任一 Server 引用的 Artifact。

不持久化可漂移的 `refCount`；GC 时根据 Server 引用计算。

### 5.1 并发与锁

所有 Artifact/Server 变更必须经过同一协调层，并使用确定的锁顺序：

```text
source identity lock → artifact digest lock
```

- 相同 `(sourceKind, sourceKey)` 的注册、更新和删除串行化。
- 写入相同 digest 时，只有一个调用者创建物理文件，其余调用者复验后复用。
- GC 获取 digest lock 后必须重新查询 Server 引用和未完成 operation，不能依据加锁前的结果删除。
- 原子移动遇到目标 content path 已存在时，复验 size/digest 后复用；不以覆盖方式写入。
- 不允许注册新引用与“删除最后引用”并发导致正在注册的 Artifact 被 GC。

## 6. 来源与保护策略

### 6.1 Hub

```text
sourceKind=hub
protected=false
registry=https://...
versionDigest=sha256:...
```

- 只接受精确 SemVer。
- 相同 Hub ref 和相同 digest 返回原 Server。
- 相同 Hub ref 返回不同 digest 时返回不可重试冲突。
- Published/Deprecated 的可拉取策略必须与 Hub 契约统一；首个目标版本按产品要求仅允许
  Published 时，Hub resolve 也必须拒绝 Deprecated，不能只依赖 UI。

### 6.2 Builtin

```text
sourceKind=builtin
protected=true
managedBy=agentos-embedded
```

- 普通 DELETE 返回 `SERVER_PROTECTED`。
- 只有 builtin reconcile 可以新增、更新、退休或移除。
- 清单删除但仍被 Tool 引用时标记 `retired`，禁止新 Run；引用释放后再 GC。
- 同一 `bundleFamily|builtinKey` 更新时原地更新 Server 的版本和 Artifact 引用，保持 Server ID、
  alias 与 Tool 关联。

### 6.3 Import / Build

```text
sourceKind=import|build
protected=false
registry=<null>
```

- 与 Hub 使用相同 Artifact 校验与内容存储。
- 本地来源由 `sourceKind` 表达，不再伪造 `native` 或 `local` Registry。
- 同 digest 重复导入不复制物理内容。
- 同本地逻辑 ref 不同 digest 返回明确冲突，由调用方选择改名、改版本或先删除旧引用。

`capabilities` 是根据 Server 状态、保护策略和 Tool 引用动态计算的 DTO，不持久化：

- `available` 且 Artifact 完整时才允许 Run。
- `retired`、`broken` 时 `canRun=false`。
- `protected=true` 或存在任意 Tool 引用时 `canRemove=false`。

## 7. Builtin Reconcile API

新增仅供本机宿主调用的管理接口：

```http
PUT /opentool-daemon/servers/builtins/reconcile
Content-Type: application/json
```

```json
{
  "bundleFamily": "agentos-embedded",
  "bundleId": "agentos-embedded@0.2.0-linux-arm64",
  "items": [
    {
      "key": "stock",
      "path": "/opt/agentos-embedded/bin/opentool-server/stock/server.ots",
      "expectedDigest": "sha256:...",
      "expectedSize": 123456
    }
  ],
  "legacyServers": [
    {"key": "stock", "serverId": "legacy-id"}
  ]
}
```

daemon 必须独立读取和校验文件，不信任调用方提供的 digest。响应返回 `created/reused/
retired/failed` 汇总和完整 builtin Server 列表。

安全与原子性要求：

1. daemon 默认只监听 loopback；reconcile 还必须校验 Embedded 注入的宿主管理凭据。凭据通过
   仅宿主与 daemon 可读的文件或启动时环境传递，不写入日志。
2. `bundleFamily` 是稳定来源身份，`bundleId` 只表示本次固件 bundle。不得从 bundleId 字符串
   猜测 family。
3. 先把所有目标文件复制到 daemon 临时区并完成 digest、size、ZIP、manifest 和平台验证，再
   修改任何现有 builtin Server 引用，避免宿主文件在校验期间变化。
4. 所有目标验证成功后一次提交 desired state。任一必要项失败时不退休旧项、不切换引用，返回
   非 2xx 结构化错误；已写入但未引用的新 Artifact 由 operation 恢复或 GC 清理。
5. `legacyServers` 必须按 builtin key 显式映射旧 Server ID，不能只传无序 ID 列表后按位置或名称
   猜测；提升为 builtin 时保留该 ID 和 alias。
6. reconcile 成功响应表示新 desired state 已持久化；Embedded 只能在此后删除旧 builtin 状态。

## 8. Pull API 与 SSE

稳定入口继续使用：

```http
POST /opentool-daemon/servers/pull
Accept: text/event-stream
```

SSE 阶段统一为：

```text
event:start  stage=resolving
event:data   stage=downloading
event:data   stage=verifying
event:data   stage=registering
event:done   stage=ready + server
event:error  code/message/retryable
```

禁止继续产生 `importing/installing/installed` 作为 Hub Pull 阶段。

取消必须贯穿到 Hub 请求和 Artifact 下载：客户端断开触发 cancellation token，关闭 sink，
删除 `.part` 和 operation，并返回或记录 `PULL_CANCELLED`。

相同 ref 的并发 Pull 首版不共享下载任务，避免一个订阅者取消影响其他订阅者；最终由 source
identity lock 和 Artifact Registry 保证幂等。若未来合并下载，必须把 Pull 建模为可订阅 operation，
广播完整进度，并在最后一个订阅者取消后才取消底层下载，不能复用首个请求的 cancellation token。

## 9. Server DTO

`GET /servers/list` 的新模型：

```json
{
  "schemaVersion": 2,
  "id": "server-id",
  "alias": "stock",
  "namespace": "litevar",
  "name": "stock",
  "version": "0.1.0",
  "artifact": {
    "digest": "sha256:...",
    "size": 123456,
    "mediaType": "application/vnd.opentool.ots",
    "platform": {"os": "linux", "arch": "arm64", "abi": "glibc"},
    "verifiedAt": "2026-08-04T00:00:00Z",
    "referenceCount": 2
  },
  "source": {
    "kind": "hub",
    "registry": "https://www.opentool-hub.com",
    "versionDigest": "sha256:..."
  },
  "policy": {
    "protected": false,
    "managedBy": "user"
  },
  "capabilities": {
    "canRun": true,
    "canRemove": true
  },
  "createdAt": "2026-08-04T00:00:00Z"
}
```

`repo/tag/installedAt` 可保留一个兼容版本，但新 daemon client、Embedded 和 CLI 必须改用
`namespace/version/createdAt`。

Tool DTO 追加 `serverId`、`materializedArtifactDigest` 和派生的 `contentState`：

```text
current | updatePending | unknown | broken
```

`contentState` 由 Tool materialized digest、Server 当前 digest/状态和工作目录完整性计算，不单独
作为第二份权威持久化。

`GET /version` 同时返回 `apiVersion` 与能力列表，例如 `artifactRegistryV2`、
`builtinReconcileV1`、`pullSseV1`。空 Server 列表也能通过该接口完成版本协商。Embedded 在调用
新 DTO 或 reconcile 前必须检查能力，不能只比较字符串版本号。

所有领域错误使用稳定 HTTP 状态与 JSON 结构，不能回退成普通 `500 error.toString()`：

```json
{"error":{"code":"SERVER_PROTECTED","message":"...","retryable":false}}
```

## 10. 删除与 GC

删除 Server 的规则：

1. `protected=true`：返回 `409 SERVER_PROTECTED`。
2. 存在任意 Tool 引用（包括停止状态）：返回 `409 SERVER_IN_USE`。首个版本不产生 orphan Tool。
3. 删除 Server 引用。
4. 若 Artifact 仍有其他 Server 引用，保留文件。
5. 若无引用，删除 Artifact 记录和 content 文件。

删除 API 的响应应说明 `artifactRemoved`，让 UI 能准确提示是否释放磁盘空间。

```json
{"serverId":"server-id","artifactRemoved":false}
```

## 11. 旧数据迁移

Hive 不提供跨 Box 事务，迁移采用 copy-on-write，不能直接原地改写唯一一份旧 `servers` Box：

1. 关闭写入口，为旧 Hive Box 创建可恢复备份；原位保留旧 Server 文件并生成 inventory，写入
   `migration_started` marker。
2. 使用新的 `artifacts_v1`、`servers_v2` 和 migration operation；旧 Box 在迁移提交前保持只读。
3. 遍历现有 `InternalServerDao` 与 `ServerDao`，流式计算旧 `.ots` digest，写入 content path 和
   `ArtifactDao`。
4. 创建新 Server 引用，保持原 Server ID、alias、namespace/name/version 和 Tool 关联。
5. registry 不是 `native/local`，并且存在 `versionDigest` 或 `artifactId` 等 Hub 元数据时推断为
   `hub`，不依赖 HTTP/HTTPS scheme。
6. `native/native`、`local/local` 以及无法可靠证明为 Hub 的历史记录迁移为 `import`。
7. Embedded 首次 builtin reconcile 通过 `legacyServers` 显式 key→serverId 映射将对应引用原地提升
   为 `builtin`，不得创建替代 Server ID。
8. 旧 Tool 的 `materializedArtifactDigest` 设为 unknown；首次需要启动时按第 3.3 节重物化。
9. 校验每个 Artifact 文件、Server→Artifact、Tool→Server 和 ID/alias 数量一致后，原子写入
   active schema marker。
10. 提交后旧 Box 和旧物理文件至少保留一个兼容/回滚周期；清理由独立、可重试步骤执行。

进程在任一步骤崩溃后，下一次启动根据 marker 和 operation 继续或回滚；重复执行迁移结果必须
一致。迁移失败时不得用半完成的新 Box 启动 Tool Runtime。

历史 build 与 import 无法可靠区分时统一迁移为 `import`，不得凭文件名猜测。

## 12. 代码模块建议

```text
lib/src/service/artifact_registry_service.dart
lib/src/service/hub_pull_service.dart
lib/src/service/builtin_reconcile_service.dart
lib/src/service/artifact_operation_service.dart
lib/src/service/tool_materialization_service.dart
lib/src/storage/artifact_storage.dart
lib/src/storage/operation_storage.dart
lib/src/service/schema_migration_service.dart
```

同步修改：

- `storage/dao.dart` 与 Hive adapters。
- `service/server_service.dart`。
- `service/tool_service.dart`。
- `controller/server_controller.dart` 与 DTO。
- `client/client.dart`。
- `router.dart`。
- `middleware.dart`：禁止读取并记录完整敏感 body；对签名 URL、宿主凭据和本地路径做结构化
  脱敏。
- `bin/config.json` 默认监听 `127.0.0.1`。

## 13. 实施门禁

### Gate A：模型与迁移

- sourceKey、Tool materialization、删除引用和错误码契约冻结。
- Artifact / Server 分离。
- 内容寻址存储。
- operation journal、恢复和 GC。
- copy-on-write 旧数据迁移保持 Server ID 与 Tool 关联。

### Gate B：统一注册管线

- Pull、Import、Build、Builtin 共用注册服务。
- protected 在 daemon 强制执行。
- builtin reconcile 原子提交并校验宿主管理凭据。
- Tool digest 不一致时按规则原子重物化。
- 新 DTO 和兼容字段。

### Gate C：客户端与宿主

- Dart daemon client 改用 Pull 命名和新 DTO。
- Embedded builtin reconcile 与 Pull BFF 接入。
- CLI 升级 daemon package 并继续使用 `opentool pull`。
- `/version` 能力协商与旧 DTO fallback 完成。

### Gate D：打包与真实设备

- macOS arm64 与 Linux arm64 二进制。
- loopback 配置与真实版本。
- 旧设备迁移、断电恢复和真实 Hub/OSS 联调。

中间 Gate 可以独立开发和测试，但不得发布 Artifact/Server 半迁移状态。

## 14. 测试与完成标准

必须覆盖：

1. 相同 `.ots` 经 builtin、import 和 Hub Pull 进入后只保存一个物理文件。
2. 同一 Artifact 可被多个 Server 引用。
3. 删除一个引用不会删除仍被其他引用使用的 Artifact。
4. 删除最后一个非 protected 引用后 Artifact 被 GC。
5. builtin 删除返回 `SERVER_PROTECTED`。
6. builtin reconcile 能新增、复用、退休和恢复。
7. Pull 取消或网络中断不留下 `.part`、operation 或半记录。
8. daemon 崩溃后启动恢复到完整或未注册状态。
9. 旧 `native/native`、`local/local` 数据迁移后 Tool 关联不丢失。
10. Pull、Import、Build、Builtin 生成的 Server 均能 Run、Load、Call、Stop。
11. 日志不记录签名 URL和本地敏感导入路径。
12. `/version`、package 和 Embedded 打包版本一致，daemon 仅监听 loopback。
13. 停止 Tool 在 Server digest 更新后原子重物化，并保留 Tool ID、alias 和 API key。
14. 运行 Tool 不热替换；停止后再启动才切换新 Artifact。
15. 任意 Tool 引用都会阻止普通 Server 删除，不产生 orphan Tool。
16. builtin reconcile 任一项失败时旧 desired state 完整保留，未授权请求被拒绝。
17. 在每个 operation stage 注入崩溃后，重启均恢复到完整旧状态或完整新状态。
18. 并发注册/删除/GC 同一 digest 不丢文件、不产生悬空引用。
19. HTTP Hub 历史记录按 Hub 元数据正确迁移，不按 scheme 误分类。
20. 相同 ref 并发 Pull 中，一个客户端取消不影响其他客户端完成。
21. Import/Build 相同 sourceKey+digest 幂等、相同 sourceKey+不同 digest 返回稳定冲突。
22. 多个 `legacyServers` 按 key 提升后分别保留正确 Server ID 与 alias。
23. `/version` 返回 apiVersion/capabilities，领域异常返回稳定 HTTP 状态和 JSON error code。
24. 请求日志不泄露宿主管理凭据、签名 URL、builtin/import 绝对路径或完整敏感 body。

## 15. 实施蓝图

本节冻结首个实现版本的文件、Box、adapter、提交顺序和 API shape。实现若要偏离，必须先同步
修改本方案及 Embedded 配套方案，不能在代码评审阶段临时改变数据语义。

### 15.1 Hive schema 与 Box

保留现有 typeId `0..3` 只读兼容，不修改其含义：

```text
0 InternalServerDaoV1
1 ServerDaoV1
2 ToolDaoV1
3 ApiKeyDao
```

新模型使用新的 adapter 和版本化 Box：

```text
typeId 4  ArtifactDaoV1          box artifacts_v1
typeId 5  ServerDaoV2            box servers_v2
typeId 6  ToolDaoV2              box tools_v2
typeId 7  ArtifactOperationDaoV1 box artifact_operations_v1
typeId 8  SchemaMetaDaoV1        box schema_meta_v1
typeId 9  BuiltinBundleDaoV1     box builtin_bundles_v1
```

首版字段冻结为：

```text
ArtifactDaoV1
  digest, size, mediaType, platformOs, platformArch, platformAbi
  filePath, manifestName, manifestVersion, verifiedAt, createdAt

ServerDaoV2
  id, alias, namespace, name, version, artifactDigest
  sourceKind, sourceKey, registry, versionDigest, hubArtifactId
  builtinBundleFamily, builtinBundleId, builtinKey
  protected, managedBy, state, createdAt

ToolDaoV2
  继承 V1 的 id/alias/tag/host/port/apiKey/status/extraCmds
  serverId, materializedArtifactDigest
  保留旧 server identity snapshot 仅用于迁移诊断，不再作为运行匹配主键

ArtifactOperationDaoV1
  id, type, stage, tempPath, digest, serverId, sourceKind, sourceKey
  payloadJson, createdAt, updatedAt

SchemaMetaDaoV1
  activeSchemaVersion, migrationState, migrationId
  sourceSchemaVersion, startedAt, committedAt, cleanupAfterVersion

BuiltinBundleDaoV1
  bundleFamily, activeBundleId, itemKeys, updatedAt
```

`capabilities`、`referenceCount` 和 Tool `contentState` 均为查询时派生字段，不进入 Hive。

### 15.2 启动、迁移与回滚

daemon 在绑定 HTTP 端口和启动 Tool autoRestore 之前同步执行：

```text
打开 schema_meta_v1
→ activeSchemaVersion == 2：恢复 operation，打开 V2 服务
→ 无 marker/V1：获取 dataDir migration 文件锁
→ 预检旧 Box、旧文件、可用空间和 adapter
→ 备份旧 Hive Box，生成旧 Server 文件 inventory
→ 创建全新的 V2 Box
→ 逐项迁移 Artifact、Server、Tool
→ 全量验证引用与数量
→ fsync 数据和 marker
→ activeSchemaVersion = 2
→ 释放迁移锁并启动 HTTP/Tool Runtime
```

- 旧 `.ots` 在提交前保持原路径不动，不额外制作第三份文件备份；同一文件系统优先 hard-link 到
  content path，hard-link 不可用时才复制，并在复制前预检空间。
- 旧 Hive 备份放入 `${OPENTOOL_PATH}/migration/<migrationId>/db-v1`，inventory 记录旧路径、size、
  digest、Server ID 和 Tool 引用。
- 迁移过程只写 V2 Box 和 content path。`activeSchemaVersion=2` 是唯一切换点。
- 切换前失败：删除或留待恢复本次 V2 临时状态，旧 Box/文件不变，daemon 以非零状态退出；升级
  流程可恢复旧 daemon 二进制。
- 切换后崩溃：只运行 V2 operation recovery，不再回写 V1。
- V2 提交并接受新写入后，直接启动旧 daemon 不是安全降级；降级必须恢复迁移前 V1 备份，并
  明确认可丢弃或另行导出 V2 期间新增的数据。
- 旧 Box 和旧路径到 `cleanupAfterVersion` 后由显式 cleanup operation 清理，不在迁移提交请求内
  删除。
- 迁移测试必须在每个步骤注入进程退出，并验证重复启动收敛到同一结果。

### 15.3 ArtifactRegistryService 提交算法

```text
register(input, reference, policy, expected)
  validate source identity and expected metadata
  create operation(stage=created)
  stream input → unique .part while hashing and counting bytes
  fsync .part
  inspect and validate only the completed .part
  acquire source identity lock
  check existing Server: same digest return existing; different digest conflict
  acquire digest lock
  if content exists: verify and reuse
  else atomic rename .part → content path and fsync parent
  write/update ArtifactDao; operation=artifactWritten
  write ServerDao; operation=referenceWritten
  notify after durable writes
  operation=committed, remove operation
  release locks
```

- expected digest/size 不匹配、ZIP/manifest/platform 校验失败时只删除 `.part` 和 operation。
- 通知失败不回滚已经持久化的数据；启动恢复或下一次 list 仍能看到已提交 Server。
- 注册输入只接受 daemon 可读取的 path 或内部 download stream，不能让远程调用方指定 content
  目标路径。

### 15.4 删除与 GC 提交算法

```text
acquire source identity lock
reload Server and all Tool references
reject protected or referenced Server
create remove operation
delete Server reference durably
acquire digest lock
recheck Server references and operations for digest
if referenced: commit artifactRemoved=false
else move content atomically to content/.trash/<operationId>
     delete ArtifactDao
     commit artifactRemoved=true
     delete trash file and operation
```

恢复时 trash 与 operation 共同决定恢复文件还是完成删除；不能看到孤立 trash 文件就直接删除。

### 15.5 Tool 原子物化

Tool 工作目录固定为 `${OPENTOOL_PATH}/tools/<toolId>`，临时目录固定在同一文件系统：

```text
tools/.staging/<toolId>-<operationId>
tools/.previous/<toolId>-<operationId>
```

重物化顺序：创建 materialize operation → 验证 Server available 和 Artifact 完整 → 解包到 staging
→ 校验入口文件 → fsync → 现目录 rename 到 previous → staging rename 到正式目录 → 更新 ToolDao
digest → operation committed → 删除 previous/operation。任一步失败均根据 operation stage 恢复
previous，且只有 ToolDao digest 与正式目录同时切换成功后才允许启动进程。每个 toolId 使用
lifecycle lock，Start/Stop/Delete/重物化不得并发修改同一目录。

### 15.6 宿主管理认证

Embedded 在启动 daemon 前生成 32-byte 随机 token，保存到仅当前系统用户可读的文件（Unix
权限 `0600`），并通过 `OPENTOOL_HOST_TOKEN_FILE=<absolute path>` 传给 daemon。daemon 启动时读取
一次并保存在内存中。

`PUT /servers/builtins/reconcile` 必须携带 `X-OpenTool-Host-Token`，使用常量时间比较；缺失或错误
返回 `403 HOST_AUTH_REQUIRED`。header、token 文件路径和 token 内容均不得写入日志。首版只有
builtin reconcile 使用此凭据，普通 loopback Tool/Pull API 行为保持兼容。

### 15.7 Builtin desired state 提交

reconcile 对同一 bundleFamily 获取独占锁，并暂时阻塞 Server list/mutation 观察中间状态：

```text
复制并验证全部输入，只 ensure Artifact、不创建 Server 引用
→ 写 builtin operation（previous snapshot + desired snapshot）
→ 按 builtinKey 排序新增/更新/retire Server 引用
→ 写 BuiltinBundleDaoV1.activeBundleId（逻辑提交点）
→ operation committed
→ 释放读写 barrier 并发送一次 servers-changed 通知
```

提交点之前异常按 previous snapshot 回滚；提交点之后异常由启动恢复完成 desired snapshot。恢复和
回滚都必须保持 legacy Server ID/alias。单次 reconcile 只发送一次列表变化通知，调用者不能观察
到半套 bundle。

### 15.8 API 冻结样例

`GET /opentool-daemon/version`：

```json
{
  "name": "OpenTool Daemon",
  "version": "0.4.0",
  "apiVersion": 2,
  "capabilities": [
    "artifactRegistryV2",
    "builtinReconcileV1",
    "pullSseV1",
    "toolMaterializationV1"
  ]
}
```

成功 reconcile：

```json
{
  "bundleFamily": "agentos-embedded",
  "bundleId": "agentos-embedded@0.2.0-linux-arm64",
  "created": ["stock"],
  "reused": ["file"],
  "retired": [],
  "failed": [],
  "servers": []
}
```

原子 reconcile 失败返回非 2xx，`failed` 包含 key/code/message，且 created/reused/retired 均不
表示已提交 desired state。DELETE、Pull 和 Import 使用第 9、10 节的统一 error/response shape。

首版稳定错误码与 HTTP 映射：

| HTTP | code |
| --- | --- |
| 400 | `INVALID_REQUEST`、`INVALID_TOOL_REFERENCE` |
| 403 | `HOST_AUTH_REQUIRED` |
| 404 | `SERVER_NOT_FOUND`、`TOOL_NOT_FOUND`、`TOOL_VERSION_NOT_FOUND` |
| 409 | `SERVER_PROTECTED`、`SERVER_IN_USE`、`ARTIFACT_SOURCE_CONFLICT` |
| 422 | `ARTIFACT_INVALID`、`ARTIFACT_DIGEST_MISMATCH`、`ARTIFACT_SIZE_MISMATCH`、`PLATFORM_NOT_SUPPORTED` |
| 502 | `HUB_UNAVAILABLE`、`ARTIFACT_DOWNLOAD_FAILED` |
| 507 | `INSUFFICIENT_STORAGE` |
| 500 | `MIGRATION_FAILED`、`REGISTER_FAILED`、`MATERIALIZATION_FAILED`、`INTERNAL_ERROR` |

SSE 中使用相同 code；主动取消使用 `PULL_CANCELLED`，不映射为普通 500。新增错误码必须向后兼容，
客户端对未知 code 显示 message 并保持 fail-closed。

### 15.9 daemon 内部提交顺序

建议拆成可独立评审的提交/PR：

1. D1：API error、`/version` capability、DTO 与新 DAO/adapter，不切换存储。
2. D2：V2 Box、copy-on-write migration、operation recovery 和故障注入测试。
3. D3：ArtifactRegistryService，先接 Import，再接 Pull、Build。
4. D4：Tool materialization、serverId 复用和删除引用约束。
5. D5：Builtin reconcile、宿主管理认证、protected/retired。
6. D6：GC、日志脱敏、完整并发/恢复/真实制品测试，生成候选 daemon 包。

D1-D6 可以在同一开发分支逐步完成，但在 D6 验收前不得发布带 V2 marker 的正式 daemon。
