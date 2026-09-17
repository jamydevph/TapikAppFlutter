class Validators {
  const Validators._();

  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email address.';
    if (!_email.hasMatch(email)) return 'Enter a valid email address.';
    return null;
  }

  static String? required(String? value, String message) {
    if (value == null || value.isEmpty) return message;
    return null;
  }

  static String? minLength(String? value, int length, String message) {
    if ((value ?? '').length < length) return message;
    return null;
  }
}
