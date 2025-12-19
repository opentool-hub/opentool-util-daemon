import 'dart:io';
import 'package:json_annotation/json_annotation.dart';
import 'package:opentool_daemon/opentool_daemon_utils.dart';
import 'exception.dart';

part 'config.g.dart';

class OpentoolfileConfigUtil {
  static Future<OpentoolfileConfig> fromFile(
    String name,
    String opentoolfilePath, {
    String? tag,
  }) async {
    final source = await File(opentoolfilePath).readAsString();
    OpentoolfileParser parser = OpentoolfileParser(source);
    Map<String, String> args = await parser.getArgs();
    Map<String, String> envs = await parser.getEnvs();
    List<String> runs = await parser.getRun();
    String? workdir = await parser.getWorkdir();
    if (workdir == null)
      throw OpentoolfileMissingArgumentException(InstructNameType.WORKDIR);
    String? entrypoint = await parser.getEntrypoint();
    if (entrypoint == null)
      throw OpentoolfileMissingArgumentException(InstructNameType.ENTRYPOINT);
    List<String> cmds = await parser.getCmd();
    OpenToolBuild build = OpenToolBuild(args: args, runs: runs);

    OpenToolRun run = OpenToolRun(
      envs: envs,
      workdir: workdir,
      entrypoint: entrypoint,
      cmds: cmds,
    );

    String os = SystemUtil.getOS();
    String cpuArch = SystemUtil.getCpuArch();

    return OpentoolfileConfig(
      name: name,
      tag: tag,
      os: os,
      cpuArch: cpuArch,
      build: build,
      run: run,
    );
  }

  static OpentoolfileConfig resolve(OpentoolfileConfig rawConfig) {
    Map<String, String> resolvedArgs = rawConfig.build.args;
    Map<String, String> resolvedEnvs = rawConfig.run.envs.map(
      (k, v) => MapEntry(k, _expand(v, resolvedArgs, {})),
    );
    List<String> resolvedRuns = rawConfig.build.runs
        .map((v) => _expand(v, resolvedArgs, resolvedEnvs))
        .toList();
    List<String> resolvedCmds = rawConfig.run.cmds
        .map((v) => _expand(v, resolvedArgs, resolvedEnvs))
        .toList();

    String workdir = _expand(rawConfig.run.workdir, resolvedArgs, resolvedEnvs);
    String entrypoint = _expand(
      rawConfig.run.entrypoint,
      resolvedArgs,
      resolvedEnvs,
    );

    return OpentoolfileConfig(
      name: rawConfig.name,
      tag: rawConfig.tag,
      os: rawConfig.os,
      cpuArch: rawConfig.cpuArch,
      build: OpenToolBuild(args: resolvedArgs, runs: resolvedRuns),
      run: OpenToolRun(
        envs: resolvedEnvs,
        workdir: workdir,
        entrypoint: entrypoint,
        cmds: resolvedCmds,
      ),
    );
  }

  static String _expand(
    String value,
    Map<String, String> args,
    Map<String, String> envs,
  ) {
    final regex = RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*');
    return value.replaceAllMapped(regex, (m) {
      final key = m[0]!.substring(1);
      if (envs.containsKey(key)) return envs[key]!;
      if (args.containsKey(key)) return args[key]!;
      return m[0]!;
    });
  }
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class OpentoolfileConfig {
  String name;
  String? tag;
  String os;
  String cpuArch;
  OpenToolBuild build;
  OpenToolRun run;

  OpentoolfileConfig({
    required this.name,
    this.tag,
    required this.os,
    required this.cpuArch,
    required this.build,
    required this.run,
  });

  factory OpentoolfileConfig.fromJson(Map<String, dynamic> json) =>
      _$OpentoolfileConfigFromJson(json);

  Map<String, dynamic> toJson() => _$OpentoolfileConfigToJson(this);
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class OpenToolBuild {
  Map<String, String> args;
  List<String> runs;
  OpenToolBuild({this.args = const {}, this.runs = const []});

  factory OpenToolBuild.fromJson(Map<String, dynamic> json) =>
      _$OpenToolBuildFromJson(json);

  Map<String, dynamic> toJson() => _$OpenToolBuildToJson(this);
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class OpenToolRun {
  Map<String, String> envs;
  String workdir;
  String entrypoint;
  List<String> cmds;
  OpenToolRun({
    this.envs = const {},
    this.workdir = '.',
    required this.entrypoint,
    this.cmds = const [],
  });

  factory OpenToolRun.fromJson(Map<String, dynamic> json) =>
      _$OpenToolRunFromJson(json);

  Map<String, dynamic> toJson() => _$OpenToolRunToJson(this);
}

// @JsonSerializable(includeIfNull: false, explicitToJson: true)
// class OpenToolServerMetadata {
//   String registry ;
//   String repo;
//   String name;
//   String tag;
//   String os;
//   String cpuArch;
//
//   OpenToolServerMetadata({
//     required this.registry,
//     required this.repo,
//     required this.name,
//     required this.tag,
//     required this.os,
//     required this.cpuArch,
//   });
//
//   factory OpenToolServerMetadata.fromJson(Map<String, dynamic> json) => _$OpenToolServerMetadataFromJson(json);
//
//   Map<String, dynamic> toJson() => _$OpenToolServerMetadataToJson(this);
// }

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class OpenToolConfig {
  String? registry;
  String? username;
  HubAuth? auth;

  OpenToolConfig({this.registry, this.username, this.auth});

  factory OpenToolConfig.fromJson(Map<String, dynamic> json) =>
      _$OpenToolConfigFromJson(json);

  Map<String, dynamic> toJson() => _$OpenToolConfigToJson(this);
}

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class HubAuth {
  final String repo;
  final String token;

  HubAuth({required this.repo, required this.token});

  factory HubAuth.fromJson(Map<String, dynamic> json) =>
      _$HubAuthFromJson(json);

  Map<String, dynamic> toJson() => _$HubAuthToJson(this);
}
