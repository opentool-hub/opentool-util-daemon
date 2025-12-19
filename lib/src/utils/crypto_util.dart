import 'package:crypto/crypto.dart';

class CryptoUtil {
  static String sha256Digest(List<int> bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
