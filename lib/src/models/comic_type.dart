import 'package:venera_core/venera_core.dart';

class ComicType {
  final int value;

  const ComicType(this.value);

  static const local = ComicType(0);

  factory ComicType.fromKey(String key) {
    return key == 'local' ? local : ComicType(key.hashCode);
  }

  String get sourceKey => this == local ? 'local' : comicSource!.key;

  ComicSource? get comicSource {
    return this == local ? null : ComicSource.fromIntKey(value);
  }

  @override
  bool operator ==(Object other) => other is ComicType && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
