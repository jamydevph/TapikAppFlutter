import '../../core/protocol/packet.dart';

enum InjectorPermission { granted, denied, unsupported }

abstract class Injector {
  InjectorPermission get permission;

  InjectorPermission refreshPermission();

  Future<void> requestPermission();

  void handle(Packet packet);

  void releaseAll();

  void dispose();
}

class UnsupportedInjector implements Injector {
  const UnsupportedInjector();

  @override
  InjectorPermission get permission => InjectorPermission.unsupported;

  @override
  InjectorPermission refreshPermission() => InjectorPermission.unsupported;

  @override
  Future<void> requestPermission() async {}

  @override
  void handle(Packet packet) {}

  @override
  void releaseAll() {}

  @override
  void dispose() {}
}
