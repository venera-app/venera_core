abstract class ListOrNull {
  static List<T>? from<T>(Iterable<dynamic>? value) {
    return value == null ? null : List<T>.from(value);
  }
}

extension ListExt<T> on List<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
