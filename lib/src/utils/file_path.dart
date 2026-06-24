import 'dart:io';

class FilePath {
  const FilePath._();

  static String join(
    String part1, [
    String? part2,
    String? part3,
    String? part4,
  ]) {
    final parts = [part1, part2, part3, part4].whereType<String>();
    return parts.join(Platform.pathSeparator);
  }
}
