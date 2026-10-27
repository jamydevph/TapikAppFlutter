import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '../../core/error/failure.dart';
import '../../core/protocol/codec.dart';
import '../../core/protocol/packet.dart';
import '../../core/protocol/packet_buffer.dart';
import '../../core/protocol/pair_detail.dart';
import '../../core/resources/constants.dart';
import '../security/agent_certificate.dart';
import '../security/datagram_seal.dart';
import '../security/paired_phone.dart';
import '../security/pairing_guard.dart';

class AgentServerState extends Equatable {
  const AgentServerState({
    this.listening = false,
    this.client,
    this.pairingCode,
    this.phones = const [],
    this.phoneId,
    this.forgetUnsaved = false,
    this.pairingOpenUntil,
    this.pairingStopped = false,
  });

  static const AgentServerState stopped = AgentServerState();

  final bool listening;
  final String? client;
  final String? pairingCode;
  final List<PairedPhone> phones;
  final String? phoneId;
  final bool forgetUnsaved;
  final DateTime? pairingOpenUntil;
  final bool pairingStopped;

  bool get hasClient => client != null;

  bool get isPairing => pairingCode != null;

  bool get isPairingOpen => pairingOpenUntil != null;

  int get pairedPhones => phones.length;

  AgentServerState withTrust({
    required List<PairedPhone> phones,
    required String? phoneId,
    required bool forgetUnsaved,
    required String? visibleCode,
    required DateTime? pairingOpenUntil,
    required bool pairingStopped,
  }) {
    return AgentServerState(
      listening: listening,
      client: client,
      pairingCode: pairingCode == null ? null : visibleCode,
      phones: phones,
      phoneId: phoneId,
      forgetUnsaved: forgetUnsaved,
      pairingOpenUntil: pairingOpenUntil,
      pairingStopped: pairingStopped,
    );
  }

  @override
  List<Object?> get props => [
    listening,
    client,
    pairingCode,
    phones,
    phoneId,
    forgetUnsaved,
    pairingOpenUntil,
    pairingStopped,
  ];
}

class AgentServer {
  AgentServer({
    required this.certificate,
    required this.guard,
    this.rememberClients,
    this.rememberHistory,
    this.peerTimeout = defaultPeerTimeout,
    this.tcpPort = TapikappConstants.tcpPort,
    this.udpPort = TapikappConstants.udpPort,
  });

  final AgentCertificate certificate;
  final PairingGuard guard;
  final Future<void> Function(Map<String, String>)? rememberClients;
  final Future<void> Function(List<PairedPhone>)? rememberHistory;
  final Duration peerTimeout;
  final int tcpPort;
  final int udpPort;

  final StreamController<AgentServerState> _states =
      StreamController<AgentServerState>.broadcast();
  final StreamController<Packet> _packets =
      StreamController<Packet>.broadcast();
  final PacketBuffer _buffer = PacketBuffer();

  AgentServerState _state = AgentServerState.stopped;
  String? _clientLabel;
  static const Duration handshakeTick = Duration(seconds: 1);
  static const Duration defaultPeerTimeout = Duration(seconds: 8);
  static const String phoneAlreadyConnected =
      'Another phone is using this laptop right now. '
      'Try again once it disconnects.';
  static const Set<PacketType> motionTypes = {
    PacketType.move,
    PacketType.scroll,
  };

  Timer? _handshake;
  Timer? _pairingTimer;
  DateTime _lastHeard = DateTime.fromMillisecondsSinceEpoch(0);
  SecureServerSocket? _server;
  RawDatagramSocket? _datagrams;
  StreamSubscription<Socket>? _accepts;
  StreamSubscription<RawSocketEvent>? _datagramReader;
  StreamSubscription<Uint8List>? _reader;
  Socket? _client;
  DatagramSeal? _seal;
  bool _forgetUnsaved = false;
  int _trustEpoch = 0;
  int _savedEpoch = 0;
  int _unsavedEpoch = 0;
  int _packetCount = 0;
  int _generation = 0;
  bool _disposed = false;

  AgentServerState get state => _state;

  Stream<AgentServerState> get states => _states.stream;

  Stream<Packet> get packets => _packets.stream;

  int get packetCount => _packetCount;

  int get pairedPhones => guard.trustedClients.length;

  List<PairedPhone> get phones => guard.pairedPhones;

  SecurityContext _securityContext() {
    return SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(certificate.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(certificate.privateKeyPem));
  }

  Future<void> start() async {
    if (_disposed) {
      throw const TransportFailure('The agent was already shut down.');
    }
    if (_state.listening) return;
    final generation = ++_generation;
    SecureServerSocket? server;
    RawDatagramSocket? datagrams;
    try {
      server = await SecureServerSocket.bind(
        InternetAddress.anyIPv6,
        tcpPort,
        _securityContext(),
      );
      if (_isStale(generation)) {
        await server.close();
        return;
      }
      datagrams = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        udpPort,
      );
      if (_isStale(generation)) {
        await server.close();
        datagrams.close();
        return;
      }
      _server = server;
      _datagrams = datagrams;
      _accepts = server.listen(_onClient, onError: (Object _) {});
      _datagramReader = datagrams.listen(
        _onDatagramEvent,
        onError: (Object _) {},
      );
      _emit(const AgentServerState(listening: true));
    } catch (error) {
      await server?.close();
      datagrams?.close();
      if (!_isStale(generation)) await stop();
      throw _failureFor(error, server == null ? tcpPort : udpPort);
    }
  }

  Future<void> stop() async {
    _generation++;
    await _dropClient();
    final accepts = _accepts;
    final datagramReader = _datagramReader;
    final server = _server;
    final datagrams = _datagrams;
    _accepts = null;
    _datagramReader = null;
    _server = null;
    _datagrams = null;
    await accepts?.cancel();
    await datagramReader?.cancel();
    datagrams?.close();
    await server?.close();
    _pairingTimer?.cancel();
    _pairingTimer = null;
    guard.closePairing();
    _emit(AgentServerState.stopped);
  }

  Future<void> disconnectClient() async {
    await _dropClient();
    _emit(AgentServerState(listening: _state.listening));
  }

  void openPairing() {
    if (!_state.listening) return;
    guard.openPairing();
    _schedulePairingEnd();
    _emit(_state);
  }

  void closePairing() {
    _pairingTimer?.cancel();
    _pairingTimer = null;
    final waiting = guard.awaitsCode;
    guard.closePairing();
    if (waiting) {
      _reply(const PairPacket(PairStage.rejected, PairingGuard.pairingClosed));
      unawaited(disconnectClient());
      return;
    }
    _emit(_state);
  }

  void _schedulePairingEnd() {
    _pairingTimer?.cancel();
    final until = guard.pairingOpenUntil;
    _pairingTimer = until == null
        ? null
        : Timer(until.difference(DateTime.now()), _onPairingEnd);
  }

  void _onPairingEnd() {
    _pairingTimer = null;
    closePairing();
  }

  Future<void> forgetAllPhones() async {
    guard.forgetAllClients();
    _trustEpoch += 1;
    if (guard.isAccepted) await disconnectClient();
    final remember = rememberClients;
    final savingAt = _trustEpoch;
    try {
      if (remember != null) await remember(guard.trustedClients);
      _savedAt(savingAt);
      _persistHistory();
    } catch (_) {
      _unsavedAt(savingAt);
      rethrow;
    } finally {
      _emit(_state);
    }
  }

  Future<void> forgetPhone(String phoneId) async {
    final connected = guard.acceptedClient == phoneId;
    final forgotten = guard.forgetClient(phoneId);
    if (forgotten == null) return;
    final forgotAt = ++_trustEpoch;
    if (connected) {
      await disconnectClient();
    } else {
      _emit(_state);
    }
    final remember = rememberClients;
    final savingAt = _trustEpoch;
    try {
      if (remember != null) await remember(guard.trustedClients);
      _savedAt(savingAt);
    } catch (_) {
      if (forgotAt == _trustEpoch) {
        guard.restore(forgotten);
      } else {
        _unsavedAt(savingAt);
      }
      rethrow;
    } finally {
      _persistHistory();
      _emit(_state);
    }
  }

  void _savedAt(int epoch) {
    if (epoch > _savedEpoch) _savedEpoch = epoch;
    if (_savedEpoch >= _unsavedEpoch) _forgetUnsaved = false;
  }

  void _unsavedAt(int epoch) {
    if (_savedEpoch >= epoch) return;
    _forgetUnsaved = true;
    if (epoch > _unsavedEpoch) _unsavedEpoch = epoch;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    await stop();
    await _states.close();
    await _packets.close();
  }

  void _onClient(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    unawaited(socket.done.catchError((Object _) => socket));
    if (_client != null) {
      if (guard.isAccepted) {
        try {
          socket.add(
            PacketCodec.encode(
              const PairPacket(PairStage.busy, phoneAlreadyConnected),
            ),
          );
        } catch (_) {}
        unawaited(
          socket
              .flush()
              .timeout(handshakeTick)
              .then<void>((_) {}, onError: (Object _) {})
              .whenComplete(socket.destroy),
        );
        return;
      }
      unawaited(_dropClient());
    }
    _client = socket;
    _clientLabel = _labelFor(socket.remoteAddress);
    _buffer.clear();
    _packetCount = 0;
    guard.open(_clientLabel!, certificate.fingerprint);
    _lastHeard = DateTime.now();
    _handshake?.cancel();
    _handshake = Timer.periodic(handshakeTick, (_) => _watchdog());
    _reader = socket.listen(
      _onBytes,
      onError: (Object _) => unawaited(disconnectClient()),
      onDone: () => unawaited(disconnectClient()),
      cancelOnError: true,
    );
    _emit(const AgentServerState(listening: true));
  }

  void _onBytes(Uint8List chunk) {
    _lastHeard = DateTime.now();
    for (final packet in _buffer.add(chunk)) {
      if (packet is PingPacket) {
        _pong();
        continue;
      }
      _deliver(packet);
    }
  }

  void _watchdog() {
    if (!guard.isAccepted) {
      if (!guard.hasTimedOut()) return;
      _reply(const PairPacket(PairStage.rejected, PairingGuard.timedOut));
      unawaited(disconnectClient());
      return;
    }
    if (DateTime.now().difference(_lastHeard) > peerTimeout) {
      unawaited(disconnectClient());
    }
  }

  void _pong() {
    final socket = _client;
    if (socket == null) return;
    try {
      socket.add(PacketCodec.encode(const PingPacket()));
    } catch (_) {}
  }

  void _onDatagramEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _datagrams?.receive();
    if (datagram == null) return;
    if (!guard.isAccepted) return;
    if (_labelFor(datagram.address) != _clientLabel) return;
    final frame = _seal?.open(datagram.data);
    if (frame == null) return;
    _lastHeard = DateTime.now();
    final packet = PacketCodec.decodeOne(frame);
    if (packet == null) return;
    if (!motionTypes.contains(packet.type)) return;
    _deliver(packet);
  }

  void _deliver(Packet packet) {
    if (!guard.isAccepted) {
      final decision = guard.onPacket(packet);
      final reply = decision.reply;
      if (reply != null) _reply(_withSessionKey(reply, decision.issuedSecret));
      if (decision.outcome == PairingOutcome.retry) {
        _reply(const PairPacket(PairStage.codeRequired));
      }
      if (!guard.isPairingOpen) {
        _pairingTimer?.cancel();
        _pairingTimer = null;
      }
      if (decision.changesTrust) {
        _persistTrust();
      } else if (decision.isAccepted) {
        _persistHistory();
      }
      if (decision.shouldDrop) {
        unawaited(disconnectClient());
        return;
      }
      if (decision.isAccepted) {
        _emit(AgentServerState(listening: true, client: _clientLabel));
      } else {
        _emit(
          AgentServerState(listening: true, pairingCode: guard.visibleCode),
        );
      }
      return;
    }
    if (packet is PairPacket) {
      if (packet.stage == PairStage.forget) _forgetClient();
      return;
    }
    _packetCount += 1;
    if (!_packets.isClosed) _packets.add(packet);
  }

  PairPacket _withSessionKey(PairPacket reply, String? secret) {
    if (reply.stage != PairStage.accepted) return reply;
    final key = DatagramSeal.newKey();
    _seal = DatagramSeal(key);
    return PairPacket(
      PairStage.accepted,
      PairDetail.accepted(DatagramSeal.encodeKey(key), secret: secret),
    );
  }

  void _forgetClient() {
    if (guard.forgetCurrentClient() != null) _persistTrust(forgot: true);
    unawaited(disconnectClient());
  }

  void _persistTrust({bool forgot = false}) {
    final savingAt = ++_trustEpoch;
    _persistHistory();
    final remember = rememberClients;
    if (remember == null) return;
    unawaited(
      remember(guard.trustedClients).then(
        (_) {
          final wasUnsaved = _forgetUnsaved;
          _savedAt(savingAt);
          if (wasUnsaved && !_forgetUnsaved) _emit(_state);
        },
        onError: (Object _) {
          if (!forgot) return;
          final wasUnsaved = _forgetUnsaved;
          _unsavedAt(savingAt);
          if (!wasUnsaved && _forgetUnsaved) _emit(_state);
        },
      ),
    );
  }

  void _persistHistory() {
    final remember = rememberHistory;
    if (remember == null) return;
    unawaited(remember(guard.pairedPhones).catchError((Object _) {}));
  }

  void _reply(PairPacket packet) {
    final socket = _client;
    if (socket == null) return;
    try {
      socket.add(PacketCodec.encode(packet));
    } catch (_) {}
  }

  Future<void> _dropClient() async {
    _handshake?.cancel();
    _handshake = null;
    final wasAccepted = guard.isAccepted;
    guard.close();
    if (!guard.isPairingOpen) {
      _pairingTimer?.cancel();
      _pairingTimer = null;
    }
    if (wasAccepted) _persistHistory();
    final reader = _reader;
    final client = _client;
    _reader = null;
    _client = null;
    _clientLabel = null;
    _seal = null;
    _buffer.clear();
    await reader?.cancel();
    client?.destroy();
  }

  bool _isStale(int generation) => _disposed || generation != _generation;

  void _emit(AgentServerState next) {
    final listening = next.listening;
    final stamped = next.withTrust(
      phones: guard.pairedPhones,
      phoneId: guard.acceptedClient,
      forgetUnsaved: _forgetUnsaved,
      visibleCode: guard.visibleCode,
      pairingOpenUntil: listening ? guard.pairingOpenUntil : null,
      pairingStopped: listening && guard.pairingStopped,
    );
    if (_state == stamped || _states.isClosed) return;
    _state = stamped;
    _states.add(stamped);
  }

  static String _labelFor(InternetAddress address) {
    const mappedPrefix = '::ffff:';
    final text = address.address;
    return text.startsWith(mappedPrefix)
        ? text.substring(mappedPrefix.length)
        : text;
  }

  static Failure _failureFor(Object error, int port) {
    if (error is Failure) return error;
    if (error is! SocketException) {
      return const TransportFailure(
        'Tapikapp could not start listening on this network.',
      );
    }
    switch (error.osError?.errorCode) {
      case 48:
      case 98:
      case 10048:
        return TransportFailure(
          'Port $port is already in use. '
          'Is another copy of Tapikapp running?',
        );
      case 13:
      case 10013:
        return TransportFailure(
          'Tapikapp is not allowed to open port $port on this computer.',
        );
      default:
        return const TransportFailure(
          'Tapikapp could not start listening on this network.',
        );
    }
  }
}
