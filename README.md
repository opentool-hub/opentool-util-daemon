# OpenTool Daemon HTTP API Documentation

English | [中文](README-zh_CN.md)

`OpenTool Daemon` provides a local persistent service for managing OpenTool Server instances. It listens on a local port and exposes HTTP endpoints for CLI or other frontend applications.

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

## Launch

```bash
./opentoold
```

By default, it listens on `http://127.0.0.1:19627`

---

## API Overview

| Method | Path        | Description                                    |
|--------|-------------|------------------------------------------------|
| GET    | `/version`  | Get version and check if the daemon is running |
| POST   | `/register` | Register a new OpenTool Server instance        |
| GET    | `/list`     | Retrieve the list of registered instances      |
| POST   | `/call`     | Forward a call request to the target instance  |
| POST   | `/load`     | Get the OpenTool Server JSON description       |
| POST   | `/stop`     | Stop an OpenTool Server instance               |
| POST   | `/remove`   | Remove an OpenTool Server instance             |

---

## 1. Version Check

**Request**

```http
GET /version
```

**Response**

```json
{
  "version": "1.0.0"
}
```

---

## 2. Register a Server Instance

**Request**

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
  "apiKeys": ["123", "456"],
  "pid": 12345
}
```

**Response**

```json
{
  "id": "<Server ID>"
}
```

---

## 3. Get All Server Instances

**Request**

```http
GET /list
```

**Response**

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

## 4. Forward a Tool Call

**Request**

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

**Response**

```json
{
  "id": "call-001",
  "result": {
    "status": "running"
  }
}
```

---

## 5. Load OpenTool JSON Description

**Request**

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

**Response**

* Follows the OpenTool Specification JSON structure.

---

## 6. Stop an OpenTool Server

**Request**

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

**Response**

```json
{
  "id": "<Server ID>",
  "status": "stopSuccess"
}
```

---

## 7. Remove an OpenTool Server Instance

**Request**

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

**Response**

```json
{
  "id": "<Server ID>",
  "status": "removeSuccess"
}
```
