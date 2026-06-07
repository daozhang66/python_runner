class ProjectPathValidator {
  static final RegExp _projectKeyPattern = RegExp(r'^[A-Za-z0-9_-]+$');
  static final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');

  const ProjectPathValidator._();

  static String normalizeProjectKey(String input) {
    final value = input.trim();
    if (value.isEmpty ||
        value != input ||
        !_projectKeyPattern.hasMatch(value) ||
        _controlChars.hasMatch(value)) {
      throw FormatException('Invalid project key: $input');
    }
    return value;
  }

  static String normalizeRelativePath(String input) {
    final value = input.trim();
    if (value.isEmpty ||
        value != input ||
        value.startsWith('/') ||
        value.contains(r'\') ||
        _controlChars.hasMatch(value)) {
      throw FormatException('Invalid project path: $input');
    }

    final parts = value.split('/');
    if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw FormatException('Invalid project path: $input');
    }
    return parts.join('/');
  }

  static String validateMainFilePath(String input) {
    final value = normalizeRelativePath(input);
    if (!value.toLowerCase().endsWith('.py')) {
      throw FormatException('Main file must be a Python file: $input');
    }
    return value;
  }
}
