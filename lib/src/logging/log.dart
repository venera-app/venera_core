import 'dart:async';

typedef ComicSourceLogHandler = void Function(String tag, Object message);
typedef LogWriter = FutureOr<void> Function(LogItem item);
typedef LogPrinter = void Function(LogItem item);

class LogItem {
  final LogLevel level;
  final String title;
  final String content;
  final DateTime time;

  LogItem(this.level, this.title, this.content, {DateTime? time})
    : time = time ?? DateTime.now();

  @override
  String toString() => "${level.name} $title $time \n$content\n\n";

  @override
  bool operator ==(Object other) {
    return other is LogItem &&
        other.level == level &&
        other.title == title &&
        other.content == content;
  }

  @override
  int get hashCode => Object.hash(level, title, content);
}

enum LogLevel { error, warning, info }

class Log {
  static final List<LogItem> _logs = <LogItem>[];

  static List<LogItem> get logs => List.unmodifiable(_logs);

  static const maxLogLength = 3000;
  static const maxLogNumber = 500;

  static bool ignoreLimitation = false;
  static bool isMuted = false;

  static LogWriter? _writer;
  static LogPrinter? _printer;

  const Log._();

  static void configure({LogWriter? writer, LogPrinter? printer}) {
    if (writer != null) _writer = writer;
    if (printer != null) _printer = printer;
  }

  static void setWriter(LogWriter? writer) {
    _writer = writer;
  }

  static void setPrinter(LogPrinter? printer) {
    _printer = printer;
  }

  static void addLog(LogLevel level, String title, String content) {
    if (isMuted) return;

    if (!ignoreLimitation && content.length > maxLogLength) {
      content = "${content.substring(0, maxLogLength)}...";
    }

    final newLog = LogItem(level, title, content);
    if (_logs.isNotEmpty && newLog == _logs.last) {
      return;
    }

    _logs.add(newLog);
    _trimLogs();

    final printer = _printer;
    if (printer != null) {
      printer(newLog);
    } else {
      _defaultPrint(newLog);
    }

    final writer = _writer;
    if (writer != null) {
      Future.sync(() => writer(newLog));
    }
  }

  static void info(String title, String content) {
    addLog(LogLevel.info, title, content);
  }

  static void warning(String title, String content) {
    addLog(LogLevel.warning, title, content);
  }

  static void error(String title, Object content, [Object? stackTrace]) {
    var info = content.toString();
    if (stackTrace != null) {
      info += "\n${stackTrace.toString()}";
    }
    addLog(LogLevel.error, title, info);
  }

  static void clear() {
    _logs.clear();
  }

  static void _trimLogs() {
    while (_logs.length > maxLogNumber) {
      final infoIndex = _logs.indexWhere(
        (element) => element.level == LogLevel.info,
      );
      if (infoIndex >= 0) {
        _logs.removeAt(infoIndex);
      } else {
        _logs.removeAt(0);
      }
    }
  }

  static void _defaultPrint(LogItem item) {
    switch (item.level) {
      case LogLevel.error:
      case LogLevel.warning:
        Zone.current.print(item.content);
      case LogLevel.info:
        assert(() {
          Zone.current.print(item.content);
          return true;
        }());
    }
  }

  @override
  String toString() {
    final buffer = StringBuffer("Logs\n\n");
    for (final log in _logs) {
      buffer.write(log);
    }
    return buffer.toString();
  }
}
