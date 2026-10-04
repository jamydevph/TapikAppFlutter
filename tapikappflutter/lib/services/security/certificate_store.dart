import 'package:shared_preferences/shared_preferences.dart';

import 'agent_certificate.dart';

class CertificateStore {
  const CertificateStore._();

  static const String certificateKey = 'agent.certificate';
  static const String privateKeyKey = 'agent.private.key';

  static Future<AgentCertificate> load(String commonName) async {
    final prefs = await SharedPreferences.getInstance();
    final storedCertificate = prefs.getString(certificateKey);
    final storedKey = prefs.getString(privateKeyKey);
    if (storedCertificate != null &&
        storedCertificate.isNotEmpty &&
        storedKey != null &&
        storedKey.isNotEmpty) {
      return AgentCertificate(
        certificatePem: storedCertificate,
        privateKeyPem: storedKey,
      );
    }
    final generated = await AgentCertificate.generate(commonName);
    await prefs.setString(certificateKey, generated.certificatePem);
    await prefs.setString(privateKeyKey, generated.privateKeyPem);
    return generated;
  }
}
