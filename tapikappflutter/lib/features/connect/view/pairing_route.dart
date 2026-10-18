class PairingRequest {
  const PairingRequest({this.laptop, this.laptopId});

  final String? laptop;
  final String? laptopId;
}

sealed class PairingResult {
  const PairingResult();
}

class PairingCodeEntered extends PairingResult {
  const PairingCodeEntered(this.code);

  final String code;
}

class PairingLaptopMismatch extends PairingResult {
  const PairingLaptopMismatch();
}
