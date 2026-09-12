sealed class Failure {
  const Failure(this.message);

  final String message;
}

class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

class TransportFailure extends Failure {
  const TransportFailure(super.message);
}

class HandshakeFailure extends Failure {
  const HandshakeFailure(super.message);
}

class InjectionFailure extends Failure {
  const InjectionFailure(super.message);
}

class UnknownFailure extends Failure {
  const UnknownFailure(super.message);
}
