# OpenTool Daemon HTTP API 文档

[English](README.md) | 中文

`OpenTool Daemon` 提供用于管理 OpenTool Server 的本地常驻守护进程服务。该服务监听本地端口，提供 HTTP 接口以供 CLI 或其他前端程序调用。

---

## Build

### Windows

```bash
dart pub get
dart compile exe bin/opentool_daemon.dart -o build/opentoold.exe
```

### macOS / Linux

```bash
dart pub get
dart compile exe bin/opentool_daemon.dart -o build/opentoold
```

---

## 启动

```bash
./opentoold
```

默认监听 `http://127.0.0.1:19627`

---

## 接口总览

| 方法   | 路径          | 描述                         |
|------|-------------|----------------------------|
| GET  | `/version`  | 版本号获取，也用于检查守护进程是否运行        |
| POST | `/register` | 注册一个新的 OpenTool Server实例   |
| GET  | `/list`     | 获取已注册实例列表                  |
| POST | `/call`     | 转发调用请求给指定实例                |
| POST | `/load`     | 返回对用OpenTool Server的JSON描述 |
| POST | `/stop`     | 关闭OpenTool Server          |
| POST | `/remove`   | 删除OpenTool Server实例        |

---

## 1. 版本检查

**请求**

```http
GET /version
```

**响应**

```json
{
  "version": "1.0.0"
}
```

---

## 2. 注册 Server 实例

**请求**

```http
POST /register
Content-Type: application/json
```

**Body**

```json
{
  "file": "<FILE PATH>",
  "host": "0.0.0.0",
  "port": 9628,
  "prefix": "/opentool",
  "apiKeys": ["123","456"],
  "pid": 12345
}
```

**响应**

```json
{
  "id": "<Server ID>"
}
```

---

## 3. 获取所有 Server 实例

**请求**

```http
GET /list
```

**响应**

```json
{
  "code": 0,
  "data": [
    {
      "id": "abc123",
      "name": "My OpenTool Server",
      "cmd": "opentool serve --port 2080",
      "pid": 12345
    }
  ]
}
```

---

## 4. 转发调用

**请求**

```http
POST /call
Content-Type: application/json
```

**Body**

```json
{
  "id": "<Server ID>",
  "call": {
    "id": "call-001",
    "name": "getStatus",
    "arguments": {}
  }
}
```

**响应**

```json
{
  "id": "call-001",
  "result": {
    "status": "running"
  }
}
```

---

## 5. 获取完整的OpenTool JSON描述

**请求**

```http
POST /load
Content-Type: application/json
```

**Body**

```json
{
  "id": "<Server ID>"
}
```

**响应**

- 详见Opentool Specification文档结构

## 6. 关闭OpenTool Server

**请求**

```http
POST /stop
Content-Type: application/json
```

**Body**

```json
{
  "id": "<Server ID>"
}
```

**响应**

```json
{
  "id": "<Server ID",
  "status": "stopSuccess"
}
```

## 6. 删除 OpenTool Server 实例

**请求**

```http
POST /remove
Content-Type: application/json
```

**Body**

```json
{
  "id": "<Server ID>"
}
```

**响应**

```json
{
  "id": "<Server ID",
  "status": "removeSuccess"
}
```
