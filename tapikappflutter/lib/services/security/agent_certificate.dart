import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/digests/sha256.dart';

class AgentCertificate {
  const AgentCertificate({
    required this.certificatePem,
    required this.privateKeyPem,
  });

  static const int keySize = 2048;
  static const int validityDays = 3650;

  final String certificatePem;
  final String privateKeyPem;

  String get fingerprint => fingerprintOfPem(certificatePem);

  static Future<AgentCertificate> generate(String commonName) async {
    final generated = await Isolate.run(() => _generate(commonName));
    return AgentCertificate(
      certificatePem: generated.first,
      privateKeyPem: generated.last,
    );
  }

  static List<String> _generate(String commonName) {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: keySize);
    final public = pair.publicKey as RSAPublicKey;
    final private = pair.privateKey as RSAPrivateKey;
    final attributes = <String, String>{'CN': commonName, 'O': 'Tapikapp'};
    final csr = X509Utils.generateRsaCsrPem(attributes, private, public);
    final certificate = X509Utils.generateSelfSignedCertificate(
      private,
      csr,
      validityDays,
      sans: [commonName],
    );
    return [certificate, CryptoUtils.encodeRSAPrivateKeyToPem(private)];
  }

  static String fingerprintOfPem(String pem) {
    return fingerprintOfDer(derFromPem(pem));
  }

  static String fingerprintOfDer(Uint8List der) {
    final digest = SHA256Digest().process(der);
    final buffer = StringBuffer();
    for (final byte in digest) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static Uint8List derFromPem(String pem) {
    final body = pem
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('-----'))
        .join();
    return base64.decode(body);
  }
}
