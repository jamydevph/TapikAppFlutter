import 'dart:math';

import '../../core/protocol/pair_detail.dart';
import '../../core/protocol/packet.dart';
import '../../core/resources/constants.dart';
import 'paired_phone.dart';
import 'reconnect_secret.dart';
import 'spake2.dart';

enum PairingOutcome { pending, retry, accepted, rejected, expired }

class PairingDecision {
  const PairingDecision({
    required this.outcome,
    this.reply,
    this.rememberClient,
    this.issuedSecret,
  });

  final PairingOutcome outcome;
  final PairPacket? reply;
  final String? rememberClient;
  final String? issuedSecret;

  bool get changesTrust => rememberClient != null;

  bool get isAccepted => outcome == PairingOutcome.accepted;

  bool get shouldDrop =>
      outcome == PairingOutcome.rejected || outcome == PairingOutcome.expired;
}

class TrustedPhone {
  const TrustedPhone(this.phone, this.secretHash);

  final PairedPhone phone;
  final String secretHash;

  String get id => phone.id;
}

class _PeerPenalty {
  _PeerPenalty(this.seenAt);

  DateTime seenAt;
  DateTime? blockedUntil;
  int attempts = 0;
}

class PairingGuard {
  PairingGuard({
    required Map<String, String> trustedClients,
    Iterable<PairedPhone> history = const [],
    this.handshakeTimeout = defaultHandshakeTimeout,
    this.codeLifetime = defaultCodeLifetime,
    this.maxAttempts = defaultMaxAttempts,
    this.pairingWindow = defaultPairingWindow,
    this.maxWrongCodesPerWindow = defaultMaxWrongCodesPerWindow,
    Random? random,
    DateTime Function()? clock,
  }) : _trusted = Map<String, String>.of(trustedClients),
       _history = {
         for (final phone in history)
           if (trustedClients.containsKey(phone.id)) phone.id: phone,
       },
       _random = random ?? Random.secure(),
       _now = clock ?? DateTime.now;

  static const Duration defaultHandshakeTimeout = Duration(seconds: 30);
  static const Duration defaultCodeLifetime = Duration(seconds: 60);
  static const Duration defaultPairingWindow = Duration(minutes: 2);
  static const int defaultMaxAttempts = 5;
  static const int defaultMaxWrongCodesPerWindow = 5;
  static const int codeLength = 6;
  static const Duration backoffStep = Duration(seconds: 2);
  static const Duration maxBackoff = Duration(minutes: 5);
  static const Duration penaltyWindow = Duration(minutes: 10);
  static const int maxTrackedPeers = 32;

  static const String outdatedPhone =
      'This phone runs an older Tapikapp. Update it, then try again.';
  static const String pairingClosed =
      'On the laptop, click “Pair a phone”, then try again.';
  static const String timedOut =
      'Pairing timed out. Pick the laptop again for a new code.';
  static const String pairingStoppedReason =
      'Too many wrong codes, so pairing stopped on the laptop. '
      'Click “Pair a phone” there to try again.';
  static const String introducedTwice =
      'That phone introduced itself twice. Pick the laptop again.';
  static const String wrongCode =
      'That code does not match the one on the laptop.';

  final Duration handshakeTimeout;
  final Duration codeLifetime;
  final int maxAttempts;
  final Duration pairingWindow;
  final int maxWrongCodesPerWindow;

  final Map<String, String> _trusted;
  final Map<String, PairedPhone> _history;
  final Random _random;
  final DateTime Function() _now;
  final Map<String, _PeerPenalty> _penalties = <String, _PeerPenalty>{};

  String _peer = '';
  String _fingerprint = '';
  String? _clientId;
  Spake2Session? _session;
  String? _code;
  DateTime? _codeExpiry;
  DateTime? _openedAt;
  bool _accepted = false;
  DateTime? _windowUntil;
  int _wrongInWindow = 0;
  bool _stopped = false;

  String? get visibleCode => _accepted || !isPairingOpen ? null : _code;

  bool get isAccepted => _accepted;

  Map<String, String> get trustedClients =>
      Map<String, String>.unmodifiable(_trusted);

  String? get acceptedClient => _accepted ? _clientId : null;

  bool get isPairingOpen {
    final until = _windowUntil;
    return until != null && _now().isBefore(until);
  }

  DateTime? get pairingOpenUntil => isPairingOpen ? _windowUntil : null;

  bool get pairingStopped => _stopped;

  bool get awaitsCode => !_accepted && _code != null;

  List<PairedPhone> get pairedPhones {
    final phones = [
      for (final id in _trusted.keys) _history[id] ?? PairedPhone(id: id),
    ]..sort(_newestFirst);
    return List<PairedPhone>.unmodifiable(phones);
  }

  static int _newestFirst(PairedPhone a, PairedPhone b) {
    final paired = _latestFirst(a.pairedAt, b.pairedAt);
    if (paired != 0) return paired;
    final seen = _latestFirst(a.lastSeenAt, b.lastSeenAt);
    return seen != 0 ? seen : a.id.compareTo(b.id);
  }

  static int _latestFirst(DateTime? a, DateTime? b) {
    if (a == null || b == null) {
      return (a == null ? 1 : 0) - (b == null ? 1 : 0);
    }
    return b.compareTo(a);
  }

  Duration? get blockedFor => blockedForPeer(_peer);

  Duration? blockedForPeer(String peer) {
    final until = _penalties[peer]?.blockedUntil;
    if (until == null) return null;
    final left = until.difference(_now());
    return left.isNegative ? null : left;
  }

  void openPairing() {
    _windowUntil = _now().add(pairingWindow);
    _wrongInWindow = 0;
    _stopped = false;
  }

  void closePairing() {
    _windowUntil = null;
    _wrongInWindow = 0;
    _stopped = false;
    if (!_accepted) {
      _code = null;
      _codeExpiry = null;
    }
  }

  void open([String peer = '', String fingerprint = '']) {
    _peer = peer;
    _fingerprint = fingerprint;
    _clientId = null;
    _session = null;
    _openedAt = _now();
    _code = null;
    _codeExpiry = null;
    _accepted = false;
    _prune();
  }

  void close() {
    final client = _clientId;
    if (_accepted && client != null && _trusted.containsKey(client)) {
      _seen(client);
    }
    if (!_accepted &&
        _session != null &&
        isPairingOpen &&
        _wrongInWindow >= maxWrongCodesPerWindow) {
      _stopPairing();
    }
    _session = null;
    _clientId = null;
    _openedAt = null;
    _code = null;
    _codeExpiry = null;
    _accepted = false;
  }

  bool hasTimedOut() {
    if (_accepted) return false;
    final opened = _openedAt;
    if (opened == null) return false;
    final limit = _code == null ? handshakeTimeout : codeLifetime;
    return _now().difference(opened) > limit;
  }

  PairingDecision onPacket(Packet packet) {
    if (_accepted) {
      return const PairingDecision(outcome: PairingOutcome.accepted);
    }
    if (packet is! PairPacket) {
      return const PairingDecision(outcome: PairingOutcome.pending);
    }
    switch (packet.stage) {
      case PairStage.hello:
      case PairStage.code:
        return _reject(outdatedPhone);
      case PairStage.introduce:
        if (_clientId != null) return _reject(introducedTwice);
        return _onIntroduce(packet.detail);
      case PairStage.resume:
        if (_clientId != null) return _reject(introducedTwice);
        return _onResume(packet.detail);
      case PairStage.spakeShare:
        return _onShare(packet.detail);
      case PairStage.spakeConfirm:
        return _onConfirm(packet.detail);
      case PairStage.accepted:
      case PairStage.rejected:
      case PairStage.codeRequired:
      case PairStage.busy:
      case PairStage.forget:
        return const PairingDecision(outcome: PairingOutcome.pending);
    }
  }

  PairingDecision _onIntroduce(String detail) {
    final parts = PairDetail.parts(detail);
    if (!_isCurrentVersion(parts)) return _reject(outdatedPhone);
    if (parts.length != 2 || !ReconnectSecret.isToken(parts[1])) {
      return _reject('That phone did not identify itself.');
    }
    _clientId = parts[1];
    return _askForCode();
  }

  PairingDecision _onResume(String detail) {
    final parts = PairDetail.parts(detail);
    if (!_isCurrentVersion(parts)) return _reject(outdatedPhone);
    if (parts.length != 3 || !ReconnectSecret.isToken(parts[1])) {
      return _reject('That phone did not identify itself.');
    }
    final clientId = parts[1];
    _clientId = clientId;
    final expected = _trusted[clientId];
    if (expected != null && ReconnectSecret.matches(parts[2], expected)) {
      _accepted = true;
      closePairing();
      _seen(clientId);
      return const PairingDecision(
        outcome: PairingOutcome.accepted,
        reply: PairPacket(PairStage.accepted),
      );
    }
    return _askForCode();
  }

  static bool _isCurrentVersion(List<String> parts) =>
      parts.first == '${TapikappConstants.protocolVersion}';

  PairingDecision _askForCode() {
    if (!isPairingOpen) {
      return _reject(_stopped ? pairingStoppedReason : pairingClosed);
    }
    if (_wrongInWindow >= maxWrongCodesPerWindow) return _stopPairing();
    final blocked = blockedFor;
    if (blocked != null) {
      return _reject(
        'Too many wrong codes. Try again in ${blocked.inSeconds + 1} seconds.',
      );
    }
    _session = null;
    final now = _now();
    _code = _newCode();
    _openedAt = now;
    _codeExpiry = now.add(codeLifetime);
    return const PairingDecision(
      outcome: PairingOutcome.pending,
      reply: PairPacket(PairStage.codeRequired),
    );
  }

  String? forgetCurrentClient() {
    final client = _clientId;
    if (!_accepted || client == null) return null;
    return _forget(client) != null ? client : null;
  }

  TrustedPhone? forgetClient(String clientId) => _forget(clientId);

  void restore(TrustedPhone trusted) {
    if (_trusted.containsKey(trusted.id)) return;
    _trusted[trusted.id] = trusted.secretHash;
    _history[trusted.id] = trusted.phone;
  }

  int forgetAllClients() {
    final forgotten = _trusted.length;
    _trusted.clear();
    _history.clear();
    return forgotten;
  }

  TrustedPhone? _forget(String clientId) {
    final hash = _trusted.remove(clientId);
    if (hash == null) return null;
    final phone = _history.remove(clientId) ?? PairedPhone(id: clientId);
    return TrustedPhone(phone, hash);
  }

  void _seen(String clientId) {
    final known = _history[clientId] ?? PairedPhone(id: clientId);
    _history[clientId] = known.seenAt(_now());
  }

  PairingDecision? _shareRefusal() {
    final expiry = _codeExpiry;
    if (!isPairingOpen) {
      _code = null;
      _codeExpiry = null;
      return _reject(_stopped ? pairingStoppedReason : pairingClosed);
    }
    if (_code == null || expiry == null || _clientId == null) {
      return _reject('Start pairing from the phone first.');
    }
    if (_now().isAfter(expiry)) {
      _code = null;
      _codeExpiry = null;
      return PairingDecision(
        outcome: PairingOutcome.expired,
        reply: const PairPacket(
          PairStage.rejected,
          'That code expired. Ask the laptop for a new one.',
        ),
      );
    }
    if (_wrongInWindow >= maxWrongCodesPerWindow) return _stopPairing();
    final blocked = blockedFor;
    if (blocked != null) {
      return _reject(
        'Too many wrong codes. Try again in ${blocked.inSeconds + 1} seconds.',
      );
    }
    if (_session != null) {
      return _reject('That phone tried a second code without finishing.');
    }
    return null;
  }

  PairingDecision _onShare(String detail) {
    final refusal = _shareRefusal();
    if (refusal != null) return refusal;
    _countAttempt();
    final share = Spake2.decode(detail, Spake2.shareLength);
    final laptop = Spake2.laptop(
      code: _code!,
      phoneId: _clientId!,
      laptopFingerprint: _fingerprint,
      random: _random,
    );
    final session = share == null ? null : laptop.finish(share);
    if (session == null) return _wrongCode();
    _session = session;
    return PairingDecision(
      outcome: PairingOutcome.pending,
      reply: PairPacket(
        PairStage.spakeShare,
        PairDetail.spakeReply(
          Spake2.encode(laptop.share),
          Spake2.encode(session.confirmB),
        ),
      ),
    );
  }

  void _countAttempt() {
    final penalty = _penaltyForPeer();
    penalty.attempts += 1;
    if (penalty.attempts >= maxAttempts) {
      penalty.blockedUntil = _now().add(_backoff(penalty.attempts));
    }
    _wrongInWindow += 1;
  }

  PairingDecision _wrongCode() {
    if (_wrongInWindow >= maxWrongCodesPerWindow) return _stopPairing();
    return _reject(wrongCode);
  }

  PairingDecision _stopPairing() {
    closePairing();
    _stopped = true;
    return _reject(pairingStoppedReason);
  }

  PairingDecision _onConfirm(String detail) {
    final session = _session;
    _session = null;
    if (session == null) {
      return _reject('Start pairing from the phone first.');
    }
    if (!isPairingOpen) {
      return _reject(_stopped ? pairingStoppedReason : pairingClosed);
    }
    if (detail.isEmpty) {
      if (_wrongInWindow >= maxWrongCodesPerWindow) return _stopPairing();
      return const PairingDecision(outcome: PairingOutcome.retry);
    }
    final tag = Spake2.decode(detail, Spake2.confirmLength);
    if (tag == null || !session.acceptsA(tag)) return _wrongCode();
    _accepted = true;
    _penalties.remove(_peer);
    _code = null;
    _codeExpiry = null;
    closePairing();
    final paired = _clientId;
    if (paired == null) {
      return const PairingDecision(
        outcome: PairingOutcome.accepted,
        reply: PairPacket(PairStage.accepted),
      );
    }
    final secret = ReconnectSecret.generate(_random);
    final now = _now();
    _trusted[paired] = ReconnectSecret.hash(secret);
    _history[paired] = PairedPhone(id: paired, pairedAt: now, lastSeenAt: now);
    return PairingDecision(
      outcome: PairingOutcome.accepted,
      reply: const PairPacket(PairStage.accepted),
      rememberClient: paired,
      issuedSecret: secret,
    );
  }

  Duration _backoff(int attempts) {
    final steps = attempts - maxAttempts + 1;
    final scaled = backoffStep * (1 << (steps - 1).clamp(0, 8));
    return scaled > maxBackoff ? maxBackoff : scaled;
  }

  _PeerPenalty _penaltyForPeer() {
    final now = _now();
    final existing = _penalties[_peer];
    if (existing != null) {
      existing.seenAt = now;
      return existing;
    }
    _prune();
    final fresh = _PeerPenalty(now);
    _penalties[_peer] = fresh;
    return fresh;
  }

  void _prune() {
    final now = _now();
    _penalties.removeWhere((_, penalty) {
      final until = penalty.blockedUntil;
      if (until != null && until.isAfter(now)) return false;
      return now.difference(penalty.seenAt) > penaltyWindow;
    });
    while (_penalties.length >= maxTrackedPeers) {
      var oldest = _penalties.keys.first;
      for (final entry in _penalties.entries) {
        if (entry.value.seenAt.isBefore(_penalties[oldest]!.seenAt)) {
          oldest = entry.key;
        }
      }
      _penalties.remove(oldest);
    }
  }

  PairingDecision _reject(String reason) {
    return PairingDecision(
      outcome: PairingOutcome.rejected,
      reply: PairPacket(PairStage.rejected, reason),
    );
  }

  String _newCode() {
    final buffer = StringBuffer();
    for (var i = 0; i < codeLength; i++) {
      buffer.write(_random.nextInt(10));
    }
    return buffer.toString();
  }
}
