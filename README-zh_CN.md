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
| Manage | POST   | `/opentool-hub/login`        | 登录 OpenTool Hub registry      |
| Manage | GET    | `/opentool-hub/user`         | 查看已缓存的账户信息                    |
| Manage | POST   | `/opentool-hub/logout`       | 清除本地凭据                        |
| Manage | POST   | `/apiKey`                    | 创建守护进程 API Key（需 sudo 令牌）     |
| Manage | GET    | `/apiKeys`                   | 列出守护进程 API Key（需 sudo 令牌）     |
| Manage | DELETE | `/apiKey/{apiKey}`           | 删除守护进程 API Key（需 sudo 令牌）     |
| Server | GET    | `/servers/list`              | 列出缓存的 OpenTool Server         |
| Server | POST   | `/servers/build`             | 根据 Opentoolfile 构建（SSE）       |
| Server | POST   | `/servers/pull`              | 从 Hub 拉取 `.ots`（SSE）          |
| Server | DELETE | `/servers/{serverId}`        | 删除指定 Server                   |
| Server | POST   | `/servers/{serverId}/tag`    | 为 Server 新增或复用 tag            |
| Server | POST   | `/servers/{serverId}/push`   | 将本地 Server 推送到 Hub（SSE）       |
| Server | GET    | `/servers/{serverId}/export` | 导出 `.ots` 到目标目录               |
| Server | POST   | `/servers/import`            | 导入外部 `.ots` 文件                |
| Server | POST   | `/servers/{serverId}/alias`  | 修改 Server 别名                  |
| Tool   | GET    | `/tools/list`                | 列出运行中的工具（或全部）                 |
| Tool   | GET    | `/tools/listWithApiKeys`     | 列出工具及其 API Key（需守护进程 API Key） |
| Tool   | POST   | `/tools/create`              | 由 Server 启动 Tool（SSE）         |
| Tool   | POST   | `/tools/{toolId}/start`      | 重新启动已存在 Tool（SSE）             |
| Tool   | POST   | `/tools/{toolId}/stop`       | 停止 Tool 进程                    |
| Tool   | DELETE | `/tools/{toolId}`            | 停止并移除 Tool                    |
| Tool   | POST   | `/tools/{toolId}/call`       | 调用 Tool 函数（JSON RPC）          |
| Tool   | POST   | `/tools/{toolId}/streamCall` | 以 SSE 方式调用 Tool               |
| Tool   | GET    | `/tools/{toolId}/load`       | 返回 OpenTool JSON 描述           |
| Tool   | POST   | `/tools/{toolId}/alias`      | 修改 Tool 别名                    |

### 关于流式接口

`/servers/build`、`/servers/pull`、`/servers/{id}/push`、`/tools/create`、`/tools/{id}/start`、`/tools/{id}/streamCall` 都返回 `text/event-stream`，事件格式如下：

```
event:START|DATA|DONE|ERROR
data:{"json":"payload"}
```

可直接复用 `lib/src/client/client.dart` 实现的 Dart 客户端，或使用任意支持 SSE 的库处理这些事件。

## 安全标头与令牌

- `x-opentool-sudo-token`：单次有效的 sudo 令牌，用于保护 API Key 管理接口。需要管理员身份生成（CLI 会调用 `SudoUtil.ensureSudoAndWriteToken`）并将令牌写入 `~/.opentool/opentool-daemon.sudo`，之后把令牌值放入 `/apiKey*` 请求头。守护进程会验证并在成功后删除或过期该文件。
- `x-opentool-api-key`：通过 `POST /apiKey` 生成的长期 API Key。访问 `/tools/listWithApiKeys` 等需要全局鉴权的接口时把此 Key 放入该头部。Key 会写入 `~/.opentool/api_keys.json`，可通过 `DELETE /apiKey/{apiKey}` 撤销。

---

## Manage API 示例

### GET /version
```json
{
  "name": "OpenTool Daemon",
  "version": "0.1.0"
}
```

### POST /opentool-hub/login
```json
{
  "registry": "https://api.opentool-hub.com",
  "username": "agent",
  "password": "secret"
}
```
返回：
```json
{
  "registry": "https://api.opentool-hub.com",
  "username": "agent"
}
```

### GET /opentool-hub/user
返回本地缓存的 registry + username。若需登出，调用 `POST /opentool-hub/logout`。

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

### POST /servers/pull?name=demo&tag=latest
把指定 Server 从 Hub 下载到临时 `.ots`，并通过 SSE 推送进度：
- `START`：`{"sizeByByte":123456,"digest":"sha256:...","pullInfoDto":{"name":"demo","tag":"latest"}}`
- `DATA`：`{"percent":42,"pullInfoDto":{...}}`
- `DONE`：回显 `pullInfoDto`，随后守护进程会自动导入该 `.ots`。

### POST /servers/{serverId}/tag?tag=stable
返回新增或复用的 Server DTO；若同一内部构建已有该 tag，则直接返回现有记录。

### POST /servers/{serverId}/push
SSE 事件示例：
- `START`：`{"serverId":"srv-1","sizeByByte":123456,"digest":"sha256..."}`
- `DATA`：`{"serverId":"srv-1","percent":42}`
- `DONE`：`{"id":"srv-1"}`

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
    "status": "RUNNING"
  }
]
```

### POST /tools/create?serverId=srv-1&hostType=local&timeout=20
基于指定 Server 启动 Tool。SSE `event:DATA` 为标准输出，`event:ERROR` 为标准错误。守护进程会在 `~/.opentool/tools/{toolId}` 中创建工作目录，并分配端口与 API Key。可用查询参数：
- `hostType`：`local`、`remote` 或留空（默认 `any`），用于传递给 Tool 运行时。
- `timeout`：在 Tool 启动较慢时，SSE 连接在指定秒数后会主动关闭，但进程会继续在后台运行。

`POST /tools/{toolId}/start?timeout=20` 对应对已有 Tool 目录的重启，并共享上述 SSE 行为。

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
返回打包在 `Opentoolfile.json` 内的 `OpenTool` 描述。使用 `POST /tools/{toolId}/alias?alias=new-name` 修改别名，`POST /tools/{toolId}/stop` 停止进程，`DELETE /tools/{toolId}` 停止并移除缓存。

---

## 客户端 SDK

`lib/src/client/client.dart` 已封装所有 Manage/Server/Tool 接口，包含 DTO、SSE 解析及错误处理，可直接在其他 Dart 项目中引用，避免重复实现 HTTP/SSE 逻辑。

需要更多细节？查看 `lib/src/controller` 中的 DTO 定义或 `lib/src/service` 了解每个接口的具体副作用。
