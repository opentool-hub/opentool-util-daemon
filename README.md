# OpenTool Daemon HTTP API Documentation

English | [中文](README-zh_CN.md)

`OpenTool Daemon` is a lightweight HTTP daemon that keeps track of local OpenTool servers and running tool processes. The daemon listens on `http://127.0.0.1:19627/opentool-daemon` by default and exposes REST + Server-Sent Event (SSE) endpoints that can be consumed by the CLI or any other automation.

---

## Build & Run

```bash
# install dependencies
dart pub get

# build release binaries
dart compile exe bin/opentool_daemon.dart -o build/opentoold  # macOS / Linux
# dart compile exe bin/opentool_daemon.dart -o build/opentoold.exe  # Windows

# run locally
dart run bin/opentool_daemon.dart --config bin/config.json
```

The daemon will persist metadata under `~/.opentool` (servers, tools, config) and write logs to `log/daemon.log`.

### Configuration

- `bin/config.json` is optional. If the file is missing or only contains `null` fields the daemon falls back to the defaults (`host: 127.0.0.1`, `port: 19627`, `prefix: /opentool-daemon`, `log.level: INFO`).
- Any field you provide overrides the default while other properties stay untouched; e.g. `{ "server": { "port": 20000 } }` keeps the host/prefix unchanged.
- The daemon always injects the `pubspec.yaml` version into the in-memory config, so you rarely need to set `version` manually.

---

## API Overview

All paths below are relative to the base prefix `/opentool-daemon`.

| Group  | Method | Path                         | Description                                                |
|--------|--------|------------------------------|------------------------------------------------------------|
| Manage | GET    | `/version`                   | Health check and daemon version                            |
| Manage | POST   | `/opentool-hub/login`        | Authenticate with an OpenTool Hub registry                 |
| Manage | GET    | `/opentool-hub/user`         | Return cached Hub user info                                |
| Manage | POST   | `/opentool-hub/logout`       | Clear stored Hub credentials                               |
| Manage | POST   | `/apiKey`                    | Create a daemon API key (requires sudo token)              |
| Manage | GET    | `/apiKeys`                   | List daemon API keys (requires sudo token)                 |
| Manage | DELETE | `/apiKey/{apiKey}`           | Delete a daemon API key (requires sudo token)              |
| Server | GET    | `/servers/list`              | List cached OpenTool servers                               |
| Server | POST   | `/servers/build`             | Build a server from an Opentoolfile (SSE stream)           |
| Server | POST   | `/servers/pull`              | Pull a server from the Hub into a temp `.ots` (SSE stream) |
| Server | DELETE | `/servers/{serverId}`        | Delete a server record                                     |
| Server | POST   | `/servers/{serverId}/tag`    | Add or reuse a tag for an existing server                  |
| Server | POST   | `/servers/{serverId}/push`   | Push a local server artifact to the Hub (SSE stream)       |
| Server | GET    | `/servers/{serverId}/export` | Copy an `.ots` to a destination folder                     |
| Server | POST   | `/servers/import`            | Import an external `.ots` file                             |
| Server | POST   | `/servers/{serverId}/alias`  | Rename a server alias                                      |
| Tool   | GET    | `/tools/list`                | List running tools (or `all` tools)                        |
| Tool   | GET    | `/tools/listWithApiKeys`     | List tools and their API keys (requires daemon API key)    |
| Tool   | POST   | `/tools/create`              | Run a tool from a server definition (SSE stream)           |
| Tool   | POST   | `/tools/{toolId}/start`      | Restart a previously created tool (SSE stream)             |
| Tool   | POST   | `/tools/{toolId}/stop`       | Stop a running tool                                        |
| Tool   | DELETE | `/tools/{toolId}`            | Stop and remove a tool                                     |
| Tool   | POST   | `/tools/{toolId}/call`       | Call a tool function (JSON RPC)                            |
| Tool   | POST   | `/tools/{toolId}/streamCall` | Stream tool responses over SSE                             |
| Tool   | GET    | `/tools/{toolId}/load`       | Return the OpenTool JSON spec                              |
| Tool   | POST   | `/tools/{toolId}/alias`      | Rename a tool alias                                        |

### Notes on Streaming Endpoints

`/servers/build`, `/servers/pull`, `/servers/{id}/push`, `/tools/create`, `/tools/{id}/start`, and `/tools/{id}/streamCall` return `text/event-stream`. Events follow this format:

```
event:START|DATA|DONE|ERROR
data:{"json":"payload"}
```

Use the client in `lib/src/client/client.dart` or any SSE-capable HTTP library to consume them.

## Security Headers & Tokens

- `x-opentool-sudo-token`: single-use header that protects the API key endpoints. Generate a token as an administrator (the CLI calls `SudoUtil.ensureSudoAndWriteToken`) which writes `~/.opentool/opentool-daemon.sudo`. There is no HTTP endpoint to mint this token, so a plain HTTP client cannot call `/apiKey*` until you first obtain the token via the CLI with sudo/admin privileges. Pass the token value in requests to `/apiKey*`; without it, API key management calls are rejected (403). The daemon validates the token against the file and deletes it (or expires it) after the first successful call.
- `x-opentool-api-key`: persistent API keys created via `POST /apiKey`. Send the key in this header when accessing `/tools/listWithApiKeys` or any other API key-gated endpoint. Keys are stored in the Hive database under `~/.opentool/db` (box name `api_keys`) and can be revoked via `DELETE /apiKey/{apiKey}`.

---

## Manage API Examples

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
Response:
```json
{
  "registry": "https://api.opentool-hub.com",
  "username": "agent"
}
```

### GET /opentool-hub/user
Returns the cached registry + username. Use `/opentool-hub/logout` (POST) to clear credentials.

### POST /apiKey (requires `x-opentool-sudo-token`)
Set the header to the temporary token dropped at `~/.opentool/opentool-daemon.sudo` and optionally name the key:
```http
POST /opentool-daemon/apiKey
x-opentool-sudo-token: <temp-token>
```
```json
{
  "name": "dev-console"
}
```
Response:
```json
{
  "name": "dev-console",
  "apiKey": "pk_opentool_123",
  "createdAt": "2024-05-01T12:30:00.000Z"
}
```

### GET /apiKeys (requires `x-opentool-sudo-token`)
Returns every stored API key using the same sudo header. Pair this endpoint with a secure UI to audit daemon access tokens.
```json
[
  {
    "name": "dev-console",
    "apiKey": "pk_opentool_123",
    "createdAt": "2024-05-01T12:30:00.000Z"
  }
]
```

### DELETE /apiKey/{apiKey} (requires `x-opentool-sudo-token`)
Removes the selected key immediately; running tools that relied on that key will fail the next privileged call.

---

## Server API Examples

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
Streams build progress for each command listed in `Opentoolfile`. `event:DATA` packets contain:
```json
{
  "script": "dart run build",
  "output": "..."
}
```
`event:DONE` closes the stream once the `.ots` artifact is stored under `~/.opentool/servers`.

### POST /servers/pull?name=demo&tag=latest
Downloads the named server from the Hub to a temporary `.ots`, emitting SSE events:
- `START`: `{ "sizeByByte": 123456, "digest": "sha256:...", "pullInfoDto": {"name": "demo", "tag": "latest"} }`
- `DATA`: `{ "percent": 42, "pullInfoDto": { ... } }` for progress updates.
- `DONE`: echoes the `PullInfoDto` once the archive is fully downloaded. The daemon automatically imports the artifact into the local cache afterwards.

### POST /servers/{serverId}/tag?tag=stable
Returns the tagged server DTO. If the tag already exists for the same internal build, the existing record is reused.

### POST /servers/{serverId}/push
SSE stream with:
- `START`: `{ "serverId": "srv-1", "sizeByByte": 123456, "digest": "sha256..." }`
- `DATA`: `{ "serverId": "srv-1", "percent": 42 }`
- `DONE`: `{ "id": "srv-1" }`

### GET /servers/{serverId}/export
Provide a JSON body `{ "path": "/tmp/output" }` describing the destination directory. The daemon copies the `.ots` into that folder using the pattern `<repo>-<name>-<tag>-<os>-<cpu>.ots`.

### POST /servers/import
```json
{
  "path": "/tmp/server.ots"
}
```
Response mirrors `OpenToolServerDto` for the imported build.

---

## Tool API Examples

### GET /tools/list?all=1
Returns every tool entry. Omit `all` or set it to `0` to only receive running tools.
Each entry may include `serverId` (nullable) to indicate the source server used when the tool was created.

### GET /tools/listWithApiKeys?all=0 (requires `x-opentool-api-key`)
Send any daemon API key via the header described earlier to receive the same tool list plus the per-tool API keys:
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

### POST /tools/create?serverId=srv-1&hostType=local&timeout=20
Starts a tool from the selected server. SSE events deliver command output (`event:DATA`) or errors (`event:ERROR`). The daemon allocates a new port, API key, and workspace under `~/.opentool/tools/{toolId}`. Optional query parameters:
- `hostType`: `local`, `remote`, or omitted for `any` (pass-through to the tool runtime).
- `timeout`: number of seconds before the daemon closes the SSE connection even if the tool keeps starting; the process continues in the background.

Optional request body (persisted on the tool and reused on restart):
```json
{
  "args": ["--foo bar", "--baz qux"]
}
```
`args` is a string array appended after the Opentoolfile `CMD` and stored with the tool; `/tools/{toolId}/start` will reuse them. It must not include `--opentoolServerTag` / `--opentoolServerHost` / `--opentoolServerPort` / `--opentoolServerApiKeys`, which are injected by the daemon; supplying them returns 400.

`POST /tools/{toolId}/start?timeout=20` exposes the same SSE behavior for restarting an existing tool directory.

### POST /tools/{toolId}/call
Request body should follow the OpenTool function-call schema:
```json
{
  "id": "call-001",
  "name": "status",
  "arguments": {"depth": 1}
}
```
Response is a `ToolReturn` JSON payload produced by the tool process.

### POST /tools/{toolId}/streamCall
Behaves like `/call`, but emits SSE packets so long-running invocations can stream tokens or intermediate results.

### GET /tools/{toolId}/load
Returns the `OpenTool` JSON description parsed from the packaged `Opentoolfile.json`. Use `/tools/{toolId}/alias?alias=new-name` (POST) to rename a tool entry, `/tools/{toolId}/stop` to stop the process, and `DELETE /tools/{toolId}` to remove it entirely (the daemon stops the process and evicts the cache entry).

---

## Client Library

`lib/src/client/client.dart` provides a strongly-typed Dart client that wraps the manage/server/tool APIs, handles SSE parsing, and mirrors every endpoint listed above. Import it in other Dart packages to integrate with the daemon without reimplementing the HTTP/SSE plumbing.

---

Need more detail? Check `lib/src/controller` for DTO definitions and `lib/src/service` for the exact side effects of each endpoint.
