import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

bool stopProcess(int pid) {
  return Process.killPid(pid);
}

String generateFixedIdByMd5(String url) {
  return md5.convert(utf8.encode(url)).toString().substring(8,24);
}