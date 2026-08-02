class ScriptNameValidator {
  static final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');
  static final RegExp _invalidFileNameChars = RegExp(r'[<>:"/\\|?*]');
  static final RegExp _reservedDeviceName = RegExp(
    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$',
    caseSensitive: false,
  );

  const ScriptNameValidator._();

  static String normalize(String input) {
    final name = input.trim();
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.endsWith('.') ||
        _invalidFileNameChars.hasMatch(name) ||
        _controlChars.hasMatch(name) ||
        _reservedDeviceName.hasMatch(name)) {
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
