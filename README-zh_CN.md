# OpenTool Daemon HTTP API 文档

[English](README.md) | 中文

`OpenTool Daemon` 是一个轻量级 HTTP 守护进程，用于管理本地 OpenTool Server 构建产物和已运行的 Tool 进程。默认监听 `http://127.0.0.1:19627/opentool-daemon` ，CLI 或任何自动化都可以通过 REST + SSE 接口访问。

---

## 构建与运行

```bash
# 安装依赖
dart pub get

# 生成发布二进制
dart compile exe bin/opentool_daemon.dart -o build/opentoold  # macOS / Linux
# dart compile exe bin/opentool_daemon.dart -o build/opentoold.exe  # Windows

# 本地运行
dart run bin/opentool_daemon.dart --config bin/config.json
```

守护进程会把元数据写入 `~/.opentool`，日志输出到 `log/daemon.log`。

### 配置

- `bin/config.json` 不是必需文件；如果缺失或其中字段为 `null`，守护进程会使用默认值（`host: 127.0.0.1`、`port: 19627`、`prefix: /opentool-daemon`、`log.level: INFO`）。
- 只需写入你想覆盖的字段即可，其余保持默认，例如 `{ "server": { "port": 20000 } }` 只会修改端口。
- 运行时会自动读取 `pubspec.yaml` 的版本号填入内存配置，通常无需显式设置 `version`。

---

## 接口总览

以下路径均以 `/opentool-daemon` 为前缀。

| 分组     | 方法     | 路径                           | 描述                            |
|--------|--------|------------------------------|-------------------------------|
| Manage | GET    | `/version`                   | 健康检查与守护进程版本                   |
| Manage | POST   | `/apiKey`                    | 创建守护进程 API Key（需 sudo 令牌）     |
| Manage | GET    | `/apiKeys`                   | 列出守护进程 API Key（需 sudo 令牌）     |
| Manage | DELETE | `/apiKey/{apiKey}`           | 删除守护进程 API Key（需 sudo 令牌）     |
| Server | GET    | `/servers/list`              | 列出缓存的 OpenTool Server         |
| Server | POST   | `/servers/build`             | 根据 Opentoolfile 构建（SSE）       |
| Server | DELETE | `/servers/{serverId}`        | 删除指定 Server                   |
| Server | POST   | `/servers/{serverId}/tag`    | 为 Server 新增或复用 tag            |
| Server | GET    | `/servers/{serverId}/export` | 导出 `.ots` 到目标目录               |
| Server | POST   | `/servers/import`            | 导入外部 `.ots` 文件                |
| Server | POST   | `/servers/{serverId}/alias`  | 修改 Server 别名                  |
| Tool   | GET    | `/tools/list`                | 列出运行中的工具（或全部）                 |
| Tool   | GET    | `/tools/listWithApiKeys`     | 列出工具及其 API Key（需守护进程 API Key） |
| Tool   | GET    | `/tools/events`              | 订阅 Tool 生命周期事件（SSE）              |
| Tool   | POST   | `/tools/create`              | 由 Server 启动 Tool（SSE）         |
| Tool   | POST   | `/tools/{toolId}/start`      | 重新启动已存在 Tool（SSE）             |
| Tool   | POST   | `/tools/{toolId}/stop`       | 停止 Tool 进程                    |
| Tool   | DELETE | `/tools/{toolId}`            | 停止并移除 Tool                    |
| Tool   | POST   | `/tools/{toolId}/call`       | 调用 Tool 函数（JSON RPC）          |
| Tool   | POST   | `/tools/{toolId}/streamCall` | 以 SSE 方式调用 Tool               |
| Tool   | GET    | `/tools/{toolId}/load`       | 返回 OpenTool JSON 描述           |
| Tool   | POST   | `/tools/{toolId}/alias`      | 修改 Tool 别名                    |

### 关于流式接口

`/servers/build`、`/tools/create`、`/tools/{id}/start`、`/tools/{id}/streamCall` 都返回 `text/event-stream`，事件格式如下：

```
event:START|DATA|DONE|ERROR
data:{"json":"payload"}
```

可直接复用 `lib/src/client/client.dart` 实现的 Dart 客户端，或使用任意支持 SSE 的库处理这些事件。

与 OpenTool Hub 同步相关的内部守护进程接口不在这份面向开发者的公开文档中展开说明。

## 安全标头与令牌

- `x-opentool-sudo-token`：单次有效的 sudo 令牌，用于保护 API Key 管理接口。需要管理员身份生成（CLI 会调用 `SudoUtil.ensureSudoAndWriteToken`）并将令牌写入 `~/.opentool/opentool-daemon.sudo`。没有任何 HTTP 接口可生成该令牌，因此纯 HTTP 客户端在未通过 CLI（且具备管理员权限）先拿到令牌前，无法调用 `/apiKey*`。之后把令牌值放入 `/apiKey*` 请求头；没有该令牌时相关 HTTP 调用会被拒绝（403）。守护进程会验证并在成功后删除或过期该文件。
- `x-opentool-api-key`：通过 `POST /apiKey` 生成的长期 API Key。访问 `/tools/listWithApiKeys` 等需要全局鉴权的接口时把此 Key 放入该头部。Key 保存在 `~/.opentool/db` 下的 Hive 数据库（box 名 `api_keys`），可通过 `DELETE /apiKey/{apiKey}` 撤销。

---

## Manage API 示例

### GET /version
```json
{
  "name": "OpenTool Daemon",
  "version": "0.1.0"
}
```

### POST /apiKey（需 `x-opentool-sudo-token`）
将请求头设为 `~/.opentool/opentool-daemon.sudo` 中的临时令牌，可选提交 Key 名称：
```http
POST /opentool-daemon/apiKey
x-opentool-sudo-token: <temp-token>
```
```json
{
  "name": "dev-console"
}
```
返回：
```json
{
  "name": "dev-console",
  "apiKey": "pk_opentool_123",
  "createdAt": "2024-05-01T12:30:00.000Z"
}
```

### GET /apiKeys（需 `x-opentool-sudo-token`）
使用相同的 sudo 标头列出当前所有 Key，便于在控制台中审计：
```json
[
  {
    "name": "dev-console",
    "apiKey": "pk_opentool_123",
    "createdAt": "2024-05-01T12:30:00.000Z"
  }
]
```

### DELETE /apiKey/{apiKey}（需 `x-opentool-sudo-token`）
立即删除指定 Key；依赖该 Key 的客户端下次访问时会被拒绝。

---

## Server API 示例

### GET /servers/list
```json
[
  {
    "id": "srv-1",
    "alias": "alpha",
    "registry": "native",
    "repo": "native",
    "name": "demo-server",
    "tag": "latest"
  }
]
```

### POST /servers/build?opentoolfile=/path/to/repo&name=demo&tag=latest
SSE `event:DATA` 中包含正在执行的脚本与输出：
```json
{
  "script": "dart run build",
  "output": "..."
}
```
`event:DONE` 表示 `.ots` 已写入 `~/.opentool/servers` 并关闭连接。

### POST /servers/{serverId}/tag?tag=stable
返回新增或复用的 Server DTO；若同一内部构建已有该 tag，则直接返回现有记录。

### GET /servers/{serverId}/export
请求体需提供目标目录：
```json
{
  "path": "/tmp/output"
}
```
守护进程会输出文件 `<repo>-<name>-<tag>-<os>-<cpu>.ots` 到该目录。

### POST /servers/import
```json
{
  "path": "/tmp/server.ots"
}
```
响应为导入后生成的 `OpenToolServerDto`。

---

## Tool API 示例

### GET /tools/list?all=1
返回全部条目；省略 `all` 或设为 `0` 时仅返回运行中的工具。
条目中可能包含 `serverId`（可为空），用于标识该 Tool 创建时来源的 Server。

### GET /tools/listWithApiKeys?all=0（需 `x-opentool-api-key`）
在请求头中携带任意守护进程 API Key，可得到附带 Tool API Key 的列表：
```json
[
  {
    "id": "tool-1",
    "alias": "alpha",
    "host": "127.0.0.1",
    "port": 9001,
    "apiKey": "tool_pk_abc",
    "status": "RUNNING",
    "serverId": "srv-1"
  }
]
```

### GET /tools/events?snapshot=1（需 `x-opentool-api-key`）
订阅守护进程管理的 Tool 生命周期事件，适合维护“当前可用 Tool 集合”的调度端或客户端。

事件语义：
- `tool.snapshot`：订阅建立后发送当前缓存中的 Tool 快照，默认开启，可通过 `snapshot=0` 关闭。
- `tool.draining`：在 Tool 真正收到 stop/delete 指令之前发出，收到后应立即把该 Tool 从可用集合中移除。
- `tool.ready`：仅当守护进程成功调用 Tool 的 `/version`，确认 Tool 已可用后才发出。
- `tool.unavailable`：守护进程检测到原本运行中的 Tool 已不可达。
- `tool.removed`：守护进程删除 Tool 元数据后发出。

示例：
```text
event:ready
data:{"message":"subscribed"}

event:tool.snapshot
data:{"type":"tool.snapshot","reason":"snapshot","tool":{"id":"tool-1","alias":"alpha","host":"127.0.0.1","port":9001,"status":"running"},"occurredAt":"2026-03-07T00:00:00.000Z"}

event:tool.draining
data:{"type":"tool.draining","reason":"stop_requested","tool":{"id":"tool-1","alias":"alpha","host":"127.0.0.1","port":9001,"status":"running"},"occurredAt":"2026-03-07T00:01:00.000Z"}

event:tool.ready
data:{"type":"tool.ready","reason":"started","tool":{"id":"tool-2","alias":"beta","host":"127.0.0.1","port":9002,"status":"running"},"occurredAt":"2026-03-07T00:01:05.000Z"}
```

### POST /tools/create?serverId=srv-1&hostType=local&timeout=20
基于指定 Server 启动 Tool。SSE `event:DATA` 为标准输出，`event:ERROR` 为标准错误。守护进程会在 `~/.opentool/tools/{toolId}` 中创建工作目录，并分配端口与 API Key。只有当 Tool 通过守护进程的就绪检查后，请求才算成功，同时 `/tools/events` 会发出 `tool.ready`。可用查询参数：
- `hostType`：`local`、`remote` 或留空（默认 `any`），用于传递给 Tool 运行时。
- `timeout`：在 Tool 启动较慢时，SSE 连接在指定秒数后会主动关闭，但进程会继续在后台运行。

可选请求体（会随 Tool 持久化，重启时继续追加）：
```json
{
  "args": ["--foo bar", "--baz qux"]
}
```
`args` 为字符串数组，会按顺序追加到 Opentoolfile 的 `CMD` 后，并保存到该 Tool；`POST /tools/{toolId}/start` 会复用这些参数。不能包含 `--opentoolServerTag` / `--opentoolServerHost` / `--opentoolServerPort` / `--opentoolServerApiKeys`，这些参数由守护进程自动注入，传入将返回 400。

`POST /tools/{toolId}/start?timeout=20` 对应对已有 Tool 目录的重启，并共享上述 SSE 行为。只有在重启后的 Tool 确认可达时，守护进程才会发出 `tool.ready`。

### POST /tools/{toolId}/call
请求遵循 OpenTool function-call 规范：
```json
{
  "id": "call-001",
  "name": "status",
  "arguments": {"depth": 1}
}
```
响应为对应的 `ToolReturn`。

### POST /tools/{toolId}/streamCall
与 `/call` 相同但通过 SSE 返回流式结果，适合长耗时任务。

### GET /tools/{toolId}/load
返回打包在 `Opentoolfile.json` 内的 `OpenTool` 描述。使用 `POST /tools/{toolId}/alias?alias=new-name` 修改别名，`POST /tools/{toolId}/stop` 停止进程，`DELETE /tools/{toolId}` 停止并移除缓存。停止前守护进程会先发出 `tool.draining`；删除时会先发 `tool.draining`，删除完成后再发 `tool.removed`。

---

## 客户端 SDK

`lib/src/client/client.dart` 已封装所有 Manage/Server/Tool 接口，包含 DTO、SSE 解析及错误处理，也支持订阅 `/tools/events`，可直接在其他 Dart 项目中引用，避免重复实现 HTTP/SSE 逻辑。

需要更多细节？查看 `lib/src/controller` 中的 DTO 定义或 `lib/src/service` 了解每个接口的具体副作用。
