/// Shared registration requirements; never changes existing login credentials.
class PasswordPolicy {
  static const requirements =
      'Use at least 8 characters, with uppercase and lowercase letters, a number, and a special character.';

  static int score(String password) => [
    password.length >= 8,
    RegExp(r'[A-Z]').hasMatch(password),
    RegExp(r'[a-z]').hasMatch(password),
    RegExp(r'[0-9]').hasMatch(password),
    RegExp(r'[^a-zA-Z0-9\s]').hasMatch(password),
  ].where((met) => met).length;

  static bool isValid(String password) => score(password) == 5;
}
