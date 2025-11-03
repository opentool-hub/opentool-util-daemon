# Opentoolfile 描述结构文档

Opentoolfile用于构建OpenTool Server的可运行二进制文件，允许开发者使用类似`Dockerfile`的方式构建OpenTool二进制可运行文件

## 命令
支持的命令包括：
- ARG：定义变量，用于**构建**(build命令)阶段使用
- ENV：定义环境变量，用于**运行**(run命令)阶段使用
- RUN：在构建阶段执行命令
- ENTRYPOINT：定义OpenTool Server启动时执行的命令
- CMD：定义OpenTool Server启动时执行命令的默认参数

## 示例
以Dart语言的mock_tool为例：
build文件：Opentoolfile
```
ARG DEFAULT_LOG=info
ENV LOG_LEVEL=$DEFAULT_LOG
ARG DEFAULT_PORT=9628
ENV PORT=$DEFAULT_PORT
RUN dart pub get
RUN dart compile exe bin/mock_tool.dart -o build/mock_tool
RUN cp mock-tool.json build/mock-tool.json
WORKDIR build
ENTRYPOINT ["mock_tool"]
CMD ["--log $LOG_LEVEL", "--port $PORT"]
```

## 构建
```bash
opentool build -t mock_tool:1.0.0
```
将会执行：
1. 找到同步路下Opentoolfile文件
2. 执行Opentoolfile文件中的RUN命令行，执行前，会替换掉ARG和ENV变量
   执行其中的命令行
    ```bash
    dart pub get
    dart compile exe bin/mock_tool.dart -o build/mock_tool
    cp mock-tool.json build/mock-tool.json
    ```
3. 创建一份`metadata.json`，内容如下：
    ```json
    {
        "id": "<SERVER_ID>",
        "alias": "<SERVER_ID>",
        "registry": "native",
        "repo": "native",
        "name": "mock_tool",
        "tag": "1.0.0",
        "os": "macos",
        "cpuArch": "arm64"
    }
    ```
4. 创建一份`OpentoolConfig`，内容如下：
    ```json
    {
      "build": {
        "args": {
          "DEFAULT_LOG": "info",
          "DEFAULT_PORT": "9628"
        },
        "run": [
           "dart pub get",
           "dart compile exe bin/mock_tool.dart -o build/mock_tool",
           "cp mock-tool.json build/mock-tool.json"
        ]
      },
      "run": {
        "envs": {
          "LOG_LEVEL": "$DEFAULT_LOG",
          "PORT": "$DEFAULT_PORT"
        },
        "workdir": "./build",
        "entrypoint": "mock_tool",
        "cmds": [
          "--log $LOG_LEVEL", 
          "--port $PORT" 
        ]
      }
    }
    ```
5. 把了一份`{WORKDIR}`文件夹、`metadata.json`、`Opentoolfile`，复制到OpenTool的系统目录中 `~/.opentool/servers/{repo}/{name}/{tag}/`，例如：`~/.opentool/servers/native/mock_tool/1.0.0/`
6. 更多：
  - 如果不写{tag}, 则默认为`latest`
  - 如果tag与现有的重复，则直接覆盖
  - 如果没有登录opentool-hub，则`{repo}`为`<none>`

## 查看
```bash
opentool servers
```
能看到已经build好的OpenTool Server信息

## 运行
```bash
opentool run mock_tool:1.0.0
```
将会执行：
1. 解析OpenTool系统目录下的`Opentoolfile`
2. OpenTool系统目录的`{WORKDIR}`作为执行目录
3. `{ENTRYPOINT}`指定的命令行，并执行`{CMD}`指定的参数
4. 增加OpenTool系统指定的参数，包括：
    ```
    --toolHost: 用于指定host，控制网络可访问的范围
    --toolPort: 用于指定port，确保端口与其他OpenTool Server的端口不冲突
    --toolApiKeys: 用于指定apiKeys，确保该Tool的安全访问
    ```

## 导出
```bash
opentool export mock_tool:1.0.0
```
将会执行：
1. 把`~/.opentool/servers/{repo}/{name}/{tag}/`完整zip成文件`{repo}-{name}-{tag}-{os}-{cpuArch}.otpkg`，例如`native-mock_tool-1.0.0-macos-arm64.otpkg`
2. 把`otpkg`文件，移动到用户执行的当前路径

## 导入
```bash
opentool import ./native-mock_tool-1.0.0-macos-arm64.otpkg
```
将会执行：
1. 解压到系统临时文件夹，文件夹名为：native-mock_tool-1.0.0-macos-arm64
    - 文件夹下有`metadata.json`、`Opentoolfile`、`{WORKDIR}`
2. 解析`metadata.json`，且移动到OpenTool系统目录下：`~/.opentool/servers/{repo}/{name}/{tag}/`，重名则覆盖