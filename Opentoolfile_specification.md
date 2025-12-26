# Opentoolfile Specification

Opentoolfile builds an OpenTool Server runnable binary. It lets developers
describe the build steps in a Dockerfile-like format.

## Commands
Supported commands:
- ARG: define variables for the build stage.
- ENV: define environment variables for the run stage.
- RUN: execute a command during build.
- ENTRYPOINT: command executed when the OpenTool Server starts.
- CMD: default arguments for the ENTRYPOINT command.

## Example
Using the Dart mock_tool as an example:

Opentoolfile:
```
# args
ARG BUILD_TOOL_NAME=mock_tool

# envs
ENV RUN_TOOL_NAME=$BUILD_TOOL_NAME
ENV NEW_VALUE_1=test1
ENV NEW_VALUE_2=test2

# build
RUN dart pub get
RUN dart compile exe bin/main.dart -o build/$BUILD_TOOL_NAME
RUN cp bin/mock_tool.json build/mock_tool.json

# run
WORKDIR build
ENTRYPOINT ["$RUN_TOOL_NAME"]
CMD ["--newValues $NEW_VALUE_1", "--newValues $NEW_VALUE_2"]
```

## Build
```bash
opentool build -t mock_tool:1.0.0
```
This will:
1. Find the `Opentoolfile` in the same directory.
2. Execute all `RUN` commands in the Opentoolfile after substituting `ARG` and
   `ENV` variables:
   ```bash
   dart pub get
   dart compile exe bin/main.dart -o build/mock_tool
   cp bin/mock_tool.json build/mock_tool.json
   ```
3. Stop generating a separate `metadata.json`; related data is stored in
   `Opentoolfile.json`.
4. Create an `OpentoolConfig`:
   ```json
   {
     "build": {
       "args": {
         "BUILD_TOOL_NAME": "mock_tool"
       },
       "run": [
          "dart pub get",
          "dart compile exe bin/main.dart -o build/mock_tool",
          "cp bin/mock_tool.json build/mock_tool.json"
       ]
     },
     "run": {
       "envs": {
         "RUN_TOOL_NAME": "$BUILD_TOOL_NAME",
         "NEW_VALUE_1": "test1",
         "NEW_VALUE_2": "test2"
       },
       "workdir": "./build",
       "entrypoint": "$RUN_TOOL_NAME",
       "cmds": [
         "--newValues $NEW_VALUE_1",
         "--newValues $NEW_VALUE_2"
       ]
     }
   }
   ```
5. Package `{WORKDIR}` and `Opentoolfile.json` into
   `~/.opentool/servers/<name>-<id>.ots` (no metadata.json and no
   `{repo}/{name}/{tag}` directory structure).
6. More:
   - If `{tag}` is omitted, it defaults to `latest`.
   - If the tag already exists, it will be overwritten.
   - If not logged in to opentool-hub, `{repo}` is `<none>`.

## View
```bash
opentool servers
```
You can see the already built OpenTool Server entries.

## Run
```bash
opentool run mock_tool:1.0.0
```
This will:
1. Read the `Opentoolfile` in the system directory.
2. Use `{WORKDIR}` as the working directory.
3. Execute `{ENTRYPOINT}` with `{CMD}` arguments.
4. The daemon appends runtime params (host/port/apiKey) automatically, so they
   are not needed in the Opentoolfile.

## Export
```bash
opentool export <serverId|name[:tag]>
```
Example:
```bash
opentool export mock_tool:1.0.0
```
This will (serverId or name[:tag] is accepted):
1. Copy/rename `~/.opentool/servers/<name>-<id>.ots` to
   `{name}-{tag}-{os}-{cpuArch}.ots`.
2. Move the `.ots` file to the current directory.

## Import
```bash
opentool import ./native-mock_tool-1.0.0-macos-arm64.ots
```
This will:
1. Unzip to a system temp folder (same-name directory) containing `build/` and
   `Opentoolfile.json`.
2. Validate `os` and `cpuArch` from `Opentoolfile.json`; if matched, copy the
   original `.ots` into `~/.opentool/servers/<name>-<id>.ots` and register a
   server record (default tag is `latest`).
