class Res<T> {
  final String? errorMessage;
  final T? _data;
  final dynamic subData;

  bool get error => errorMessage != null;
  bool get success => !error;
  T get data => _data ?? (throw Exception(errorMessage));
  T? get dataOrNull => _data;

  const Res(this._data, {this.errorMessage, this.subData});

  const Res.error(String err)
    : _data = null,
      subData = null,
      errorMessage = err;

  Res.fromErrorRes(Res another, {this.subData})
    : _data = null,
      errorMessage = another.errorMessage;

  @override
  String toString() => _data.toString();
}
