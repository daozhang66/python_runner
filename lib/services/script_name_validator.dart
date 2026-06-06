class ScriptNameValidator {
  static final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');

  const ScriptNameValidator._();

  static String normalize(String input) {
    final name = input.trim();
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains(r'\') ||
        _controlChars.hasMatch(name)) {
      throw FormatException('Invalid script name: $input');
    }
    return name;
  }

  static String? tryNormalize(String input) {
    try {
      return normalize(input);
    } on FormatException {
      return null;
    }
  }
}
