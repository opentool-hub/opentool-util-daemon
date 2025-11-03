import 'dart:io';

class SystemUtil {
  static String getOS() {
    return Platform.operatingSystem; // linux, windows, macos
  }

  static String getCpuArch() {
    String arch = "unknown";

    final match = RegExp(r'on\s+"(.+)"').firstMatch(Platform.version);
    if (match != null) {
      final raw = match.group(1)!; // e.g. windows_x64, macos_arm64, linux_ia32
      if (raw.contains("x64")) arch = "x64";
      else if (raw.contains("ia32")) arch = "x86";
      else if (raw.contains("arm64")) arch = "arm64";
      else if (raw.contains("arm")) arch = "arm32";
    }
    return arch;
  }
}