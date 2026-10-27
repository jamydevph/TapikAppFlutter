import '../resources/constants.dart';

class PairDetail {
  const PairDetail._();

  static const String separator = ' ';

  static String introduce(String clientId) =>
      [TapikappConstants.protocolVersion, clientId].join(separator);

  static String resume(String clientId, String secret) =>
      [TapikappConstants.protocolVersion, clientId, secret].join(separator);

  static String accepted(String sealKey, {String? secret}) =>
      secret == null ? sealKey : [sealKey, secret].join(separator);

  static String spakeReply(String share, String confirm) =>
      [share, confirm].join(separator);

  static List<String> parts(String detail) => detail.split(separator);
}
