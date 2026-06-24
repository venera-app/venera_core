import 'dart:async';

abstract mixin class Init {
  bool _isInit = false;
  bool _isInitializing = false;
  final _initCompleters = <Completer<void>>[];

  Future<void> ensureInit() async {
    if (_isInit) return;
    if (!_isInitializing) {
      unawaited(init());
    }
    final completer = Completer<void>();
    _initCompleters.add(completer);
    return completer.future;
  }

  Future<void> init() async {
    if (_isInit || _isInitializing) {
      return ensureInit();
    }
    _isInitializing = true;
    try {
      await doInit();
      _isInit = true;
      for (final completer in _initCompleters) {
        if (!completer.isCompleted) completer.complete();
      }
    } catch (e, s) {
      for (final completer in _initCompleters) {
        if (!completer.isCompleted) completer.completeError(e, s);
      }
      rethrow;
    } finally {
      _initCompleters.clear();
      _isInitializing = false;
    }
  }

  Future<void> doInit();
}
