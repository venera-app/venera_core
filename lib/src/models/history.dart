class HistoryType {
  final int value;

  const HistoryType(this.value);
}

abstract mixin class HistoryMixin {
  String get title;
  String? get subTitle;
  String get cover;
  int? get maxPage;
  HistoryType get historyType;
  String get id;
}
