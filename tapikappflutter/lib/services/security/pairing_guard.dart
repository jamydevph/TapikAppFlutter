import 'dart:math';

import '../../core/protocol/packet.dart';
import 'paired_phone.dart';

enum PairingOutcome { pending, retry, accepted, rejected, expired }

class PairingDecision {
  const PairingDecision({
    required this.outcome,
    this.reply,
    this.rememberClient,
    this.forgotClient,
  });

  final PairingOutcome outcome;
  final PairPacket? reply;
  final String? rememberClient;
  final String? forgotClient;

  bool get changesTrust => rememberClient != null || forgotClient != null;

  bool get isAccepted => outcome == PairingOutcome.accepted;

  bool get shouldDrop =>
      outcome == PairingOutcome.rejected || outcome == PairingOutcome.expired;
}

class _PeerPenalty {
  _PeerPenalty(this.seenAt);

  DateTime seenAt;
  DateTime? blockedUntil;
  int attempts = 0;
}

class PairingGuard {
  PairingGuard({
    required Set<String> trustedClients,
    Iterable<PairedPhone> history = const [],
    this.handshakeTimeout = defaultHandshakeTimeout,
    this.codeLifetime = defaultCodeLifetime,
    this.maxAttempts = defaultMaxAttempts,
    Random? random,
    DateTime Function()? clock,
  }) : _trusted = Set<String>.of(trustedClients),
       _history = {
         for (final phone in history)
           if (trustedClients.contains(phone.id)) phone.id: phone,
       },
       _random = random ?? Random.secure(),
       _now = clock ?? DateTime.now;

  static const Duration defaultHandshakeTimeout = Duration(seconds: 30);
  static const Duration defaultCodeLifetime = Duration(seconds: 60);
  static const int defaultMaxAttempts = 5;
  static const int codeLength = 6;
  static const Duration backoffStep = Duration(seconds: 2);
  static const Duration maxBackoff = Duration(minutes: 5);
  static const Duration penaltyWindow = Duration(minutes: 10);
  static const int maxTrackedPeers = 32;

  final Duration handshakeTimeout;
  final Duration codeLifetime;
  final int maxAttempts;

  final Set<String> _trusted;
  final Map<String, PairedPhone> _history;
  final Random _random;
  final DateTime Function() _now;
  final Map<String, _PeerPenalty> _penalties = <String, _PeerPenalty>{};

  String _peer = '';
  String? _clientId;
  String? _code;
  DateTime? _codeExpiry;
  DateTime? _openedAt;
  bool _accepted = false;

  String? get visibleCode => _accepted ? null : _code;

  bool get isAccepted => _accepted;

  Set<String> get trustedClients => Set<String>.unmodifiable(_trusted);

  String? get acceptedClient => _accepted ? _clientId : null;

  List<PairedPhone> get pairedPhones {
    final phones = [
      for (final id in _trusted) _history[id] ?? PairedPhone(id: id),
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

  void open([String peer = '']) {
    _peer = peer;
    _clientId = null;
    _openedAt = _now();
    _code = null;
    _codeExpiry = null;
    _accepted = false;
    _prune();
  }

  void close() {
    final client = _clientId;
    if (_accepted && client != null && _trusted.contains(client)) {
      _seen(client);
    }
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
    return _now().difference(opened) > handshakeTimeout;
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
        return _onHello(packet.detail, introduce: false);
      case PairStage.introduce:
        return _onHello(packet.detail, introduce: true);
      case PairStage.code:
        return _onCode(packet.detail);
      case PairStage.accepted:
      case PairStage.rejected:
      case PairStage.codeRequired:
      case PairStage.forget:
        return const PairingDecision(outcome: PairingOutcome.pending);
    }
  }

  PairingDecision _onHello(String clientId, {required bool introduce}) {
    if (clientId.isEmpty) {
      return _reject('That phone did not identify itself.');
    }
    _clientId = clientId;
    final forgot = introduce && _forget(clientId) != null ? clientId : null;
    if (!introduce && _trusted.contains(clientId)) {
      _accepted = true;
      _seen(clientId);
      return PairingDecision(
        outcome: PairingOutcome.accepted,
        reply: const PairPacket(PairStage.accepted),
      );
    }
    final blocked = blockedFor;
    if (blocked != null) {
      return _reject(
        'Too many wrong codes. Try again in ${blocked.inSeconds + 1} seconds.',
        forgotClient: forgot,
      );
    }
    _code = _newCode();
    _codeExpiry = _now().add(codeLifetime);
    return PairingDecision(
      outcome: PairingOutcome.pending,
      reply: const PairPacket(PairStage.codeRequired),
      forgotClient: forgot,
    );
  }

  String? forgetCurrentClient() {
    final client = _clientId;
    if (!_accepted || client == null) return null;
    return _forget(client) != null ? client : null;
  }

  PairedPhone? forgetClient(String clientId) => _forget(clientId);

  void restore(PairedPhone phone) {
    if (!_trusted.add(phone.id)) return;
    _history[phone.id] = phone;
  }

  int forgetAllClients() {
    final forgotten = _trusted.length;
    _trusted.clear();
    _history.clear();
    return forgotten;
  }

  PairedPhone? _forget(String clientId) {
    if (!_trusted.remove(clientId)) return null;
    return _history.remove(clientId) ?? PairedPhone(id: clientId);
  }

  void _seen(String clientId) {
    final known = _history[clientId] ?? PairedPhone(id: clientId);
    _history[clientId] = known.seenAt(_now());
  }

  PairingDecision _onCode(String entered) {
    final expected = _code;
    final expiry = _codeExpiry;
    if (expected == null || expiry == null) {
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
    final blocked = blockedFor;
    if (blocked != null) {
      return _reject(
        'Too many wrong codes. Try again in ${blocked.inSeconds + 1} seconds.',
      );
    }
    if (entered != expected) {
      final penalty = _penaltyForPeer();
      penalty.attempts += 1;
      if (penalty.attempts >= maxAttempts) {
        penalty.blockedUntil = _now().add(_backoff(penalty.attempts));
      }
      return PairingDecision(
        outcome: PairingOutcome.retry,
        reply: const PairPacket(
          PairStage.rejected,
          'That code does not match the one on the laptop.',
        ),
      );
    }
    _accepted = true;
    _penalties.remove(_peer);
    _code = null;
    _codeExpiry = null;
    final paired = _clientId;
    if (paired != null) {
      final now = _now();
      _trusted.add(paired);
      _history[paired] = PairedPhone(
        id: paired,
        pairedAt: now,
        lastSeenAt: now,
      );
    }
    return PairingDecision(
      outcome: PairingOutcome.accepted,
      reply: const PairPacket(PairStage.accepted),
      rememberClient: paired,
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

  PairingDecision _reject(String reason, {String? forgotClient}) {
    return PairingDecision(
      outcome: PairingOutcome.rejected,
      reply: PairPacket(PairStage.rejected, reason),
      forgotClient: forgotClient,
    );
  }

  String _newCode() {
    final buffer = StringBuffer();
    for (var i = 0; i < codeLength; i++) {
      buffer.write(_random.nextInt(10));
    }
    return buffer.toString();
  }

  void trust(String clientId) {
    if (clientId.isEmpty) return;
    _trusted.add(clientId);
  }
}
