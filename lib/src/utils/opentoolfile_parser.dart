class InstructNameType {
  static const String ARG = 'ARG';  // for build mode
  static const String ENV = 'ENV';  // for run mode
  static const String RUN = 'RUN';  // script for build mode
  static const String WORKDIR = 'WORKDIR';  // work dir for run mode
  static const String ENTRYPOINT = 'ENTRYPOINT';  // command for run mode
  static const String CMD = 'CMD';  // default command arguments for run mode
}

class Instruction {
  final String name;
  final List<String> args;
  final int line;
  final String? blockComment;
  final String? inlineComment;

  Instruction(this.name, this.args, this.line, {this.blockComment, this.inlineComment});
}
/// Represents the runtime context used for variable expansion.
class ExecutionContext {
  final Map<String, String> args = {};
  final Map<String, String> envs = {};
  String workdir = '/';
  String? entrypoint;
  List<String> cmd = [];

  /// Expand variables like `$VAR` using ARG/ENV definitions.
  String expand(String value) {
    final regex = RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*');
    return value.replaceAllMapped(regex, (m) {
      final key = m[0]!.substring(1);
      if (envs.containsKey(key)) return envs[key]!;
      if (args.containsKey(key)) return args[key]!;
      return m[0]!; // leave unresolved
    });
  }
}

/// Main parser and interpreter for Opentoolfile.
/// It parses the file into a flat list of instructions
/// and builds a contextual environment for variable expansion.
class OpentoolfileParser {
  /// Parsed instruction list (acts as AST).
  late final List<Instruction> _instructions;

  /// Execution context after interpretation.
  final ExecutionContext context = ExecutionContext();

  /// Constructor: parse and interpret the given Opentoolfile source.
  OpentoolfileParser(String source) {
    _instructions = _parse(source);
    _interpret();
  }

  // ---------------------------------------------------------------------------
  // Public getters (high-level access)
  // ---------------------------------------------------------------------------

  /// Get ARG definitions.
  Map<String, String> getArgs() => Map.unmodifiable(context.args);

  /// Get ENV definitions (with ARG-expanded values).
  Map<String, String> getEnvs() => Map.unmodifiable(context.envs);

  /// Get all RUN commands (expanded).
  List<String> getRun() {
    return _instructions
        .where((i) => i.name == InstructNameType.RUN)
        .map((i) => context.expand(i.args.join(' ')))
        .toList();
  }

  /// Get WORKDIR (expanded).
  String? getWorkdir() {
    final instr = _instructions.lastWhere(
          (i) => i.name == InstructNameType.WORKDIR,
      orElse: () => Instruction('NONE', [], 0),
    );
    return instr.args.isNotEmpty ? context.expand(instr.args.join(' ')) : null;
  }

  /// Get ENTRYPOINT (expanded).
  String? getEntrypoint() {
    final instr = _instructions.lastWhere(
          (i) => i.name == InstructNameType.ENTRYPOINT,
      orElse: () => Instruction('NONE', [], 0),
    );
    return instr.args.isNotEmpty ? context.expand(instr.args.first) : null;
  }

  /// Get CMD arguments (expanded).
  List<String> getCmd() {
    final instr = _instructions.lastWhere(
          (i) => i.name == InstructNameType.CMD,
      orElse: () => Instruction('NONE', [], 0),
    );
    return instr.args.map(context.expand).toList();
  }

  /// Get final command = ENTRYPOINT + CMD (expanded).
  List<String> getFinalCommand() {
    final entry = getEntrypoint();
    final cmd = getCmd();
    return [if (entry != null) entry, ...cmd];
  }

  // ---------------------------------------------------------------------------
  // Internal parsing and interpretation
  // ---------------------------------------------------------------------------

  /// Parse raw text into a flat list of instructions.
  List<Instruction> _parse(String source) {
    final lines = source.split('\n');
    final result = <Instruction>[];
    String? lastBlockComment;

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      var line = raw.trim();
      if (line.isEmpty) continue;

      String? inlineComment;

      // Handle comments
      if (line.contains('#')) {
        final idx = line.indexOf('#');
        if (idx == 0) {
          // full-line comment -> treat as block comment
          lastBlockComment = line.substring(1).trim();
          continue;
        } else {
          // inline comment
          inlineComment = line.substring(idx + 1).trim();
          line = line.substring(0, idx).trim();
        }
      }

      if (line.isEmpty) continue;

      // Split into command + args
      final parts = _splitArgs(line);
      final name = parts.first.toUpperCase();
      final args = parts.skip(1).toList();

      result.add(Instruction(
        name,
        args,
        i + 1,
        blockComment: lastBlockComment,
        inlineComment: inlineComment,
      ));

      lastBlockComment = null;
    }

    return result;
  }

  /// Simulate execution to build the runtime context.
  void _interpret() {
    for (final instr in _instructions) {
      switch (instr.name) {
        case InstructNameType.ARG:
          for (var arg in instr.args) {
            final parts = arg.split('=');
            if (parts.length == 2) {
              context.args[parts[0]] = parts[1];
            }
          }
          break;

        case InstructNameType.ENV:
          for (var arg in instr.args) {
            final parts = arg.split('=');
            if (parts.length == 2) {
              context.envs[parts[0]] = context.expand(parts[1]);
            }
          }
          break;

        case InstructNameType.WORKDIR:
          context.workdir = context.expand(instr.args.join(' '));
          break;

        case InstructNameType.ENTRYPOINT:
          if (instr.args.isNotEmpty) {
            context.entrypoint = context.expand(instr.args.first);
          }
          break;

        case InstructNameType.CMD:
          context.cmd = instr.args.map(context.expand).toList();
          break;

        default:
        // RUN and other instructions do not affect context.
          break;
      }
    }
  }

  /// Split instruction arguments.
  /// Supports both space-delimited and JSON-array-like syntax.
  List<String> _splitArgs(String line) {
    final jsonArray = RegExp(r'^\w+\s+\[.*\]$');
    if (jsonArray.hasMatch(line)) {
      final name = line.split(RegExp(r'\s+')).first;
      final arr = line.substring(name.length).trim();
      final args = arr
          .substring(1, arr.length - 1)
          .split(',')
          .map((s) => s.trim().replaceAll('"', ''))
          .where((s) => s.isNotEmpty)
          .toList();
      return [name, ...args];
    }
    return line.split(RegExp(r'\s+'));
  }
}