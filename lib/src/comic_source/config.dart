part of 'comic_source.dart';

class _Config {
  static String dataPath = "";
  static String appVersion = '1.0.0';
  static String locale = "en_US";
  static String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  static Dio dio = Dio();
  static VoidCallback? dataChangedHandler;

  static void update({
    String? dataPath,
    String? appVersion,
    String? locale,
    String? userAgent,
    Dio? dio,
    VoidCallback? dataChangedHandler,
  }) {
    if (dataPath != null) {
      _Config.dataPath = dataPath;
    }
    if (appVersion != null) {
      _Config.appVersion = appVersion;
    }
    if (locale != null) {
      _Config.locale = locale;
    }
    if (userAgent != null) {
      _Config.userAgent = userAgent;
    }
    if (dio != null) {
      _Config.dio = dio;
    }
    if (dataChangedHandler != null) {
      _Config.dataChangedHandler = dataChangedHandler;
    }
  }
}
