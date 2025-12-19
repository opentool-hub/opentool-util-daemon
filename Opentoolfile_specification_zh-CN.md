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
RUN dart pub get
RUN dart compile exe bin/mock_tool.dart -o build/mock_tool
RUN cp mock-tool.json build/mock-tool.json
WORKDIR build
ENTRYPOINT ["mock_tool"]
CMD ["--log $LOG_LEVEL"]
```

## 构建
```bash
opentool build -t mock_tool:1.0.0
```
将会执行：
1. 找到同目录下的 Opentoolfile 文件
2. 执行Opentoolfile文件中的RUN命令行，执行前，会替换掉ARG和ENV变量
   执行其中的命令行
    ```bash
    dart pub get
    dart compile exe bin/mock_tool.dart -o build/mock_tool
    cp mock-tool.json build/mock-tool.json
    ```
3. 不再生成独立的 `metadata.json`；相关信息会写入 `Opentoolfile.json`。
4. 创建一份`OpentoolConfig`，内容如下：
    ```json
    {
      "build": {
        "args": {
          "DEFAULT_LOG": "info"
        },
        "run": [
           "dart pub get",
           "dart compile exe bin/mock_tool.dart -o build/mock_tool",
           "cp mock-tool.json build/mock-tool.json"
        ]
      },
      "run": {
        "envs": {
          "LOG_LEVEL": "$DEFAULT_LOG"
        },
        "workdir": "./build",
        "entrypoint": "mock_tool",
        "cmds": [
          "--log $LOG_LEVEL"
        ]
      }
    }
    ```
5. 将 `{WORKDIR}` 文件夹与 `Opentoolfile.json` 打包为 `~/.opentool/servers/<name>-<id>.ots`（无 metadata.json、无 {repo}/{name}/{tag} 目录层级）
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
4. 守护进程自动附加参数（如 host/port/apiKey），无需在 Opentoolfile 中配置默认端口。

## 导出
```bash
opentool export mock_tool:1.0.0
```
将会执行：
1. 将 `~/.opentool/servers/<name>-<id>.ots` 拷贝/重命名为 `{name}-{tag}-{os}-{cpuArch}.ots`
2. 将 `.ots` 文件移动到当前路径

## 导入
```bash
opentool import ./native-mock_tool-1.0.0-macos-arm64.ots
```
将会执行：
1. 解压到系统临时文件夹（同名目录），目录下包含 `build/` 与 `Opentoolfile.json`。
2. 校验 `Opentoolfile.json` 中的 `os` 和 `cpuArch`；通过后将原始 `.ots` 拷贝到 `~/.opentool/servers/<name>-<id>.ots` 并注册一条 server 记录（tag 缺省为 `latest`）。
