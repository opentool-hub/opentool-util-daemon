import 'dart:convert';
import 'dart:io';

class JsonFileUtil {
  static Future<void> saveToFile(Map<String, dynamic> jsonObject, String dirPath, String fileName) async {
    final directory = Directory(dirPath);

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final filePath = '${directory.path}${Platform.pathSeparator}$fileName';

    final file = File(filePath);
    final jsonString = const JsonEncoder.withIndent('  ').convert(jsonObject);
    await file.writeAsString(jsonString);
  }

  static Future<Map<String, dynamic>> readFromFile(String jsonFilePath) async {
    final file = File(jsonFilePath);

    if (!await file.exists()) {
      throw FileSystemException('File not found', jsonFilePath);
    }

    final contents = await file.readAsString();

    final data = jsonDecode(contents);

    if (data is! Map<String, dynamic>) {
      throw FormatException('JSON root element must be an object');
    }

    return data;
  }
}