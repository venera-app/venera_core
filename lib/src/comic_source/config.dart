part of 'comic_source.dart';

class _Config {
  static String dataPath = "";
  static String appVersion = '1.0.0';
  static String locale = "en_US";
  static String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  static Dio dio = Dio();
  static CookieJarSql? cookieJar;
  static VoidCallback? dataChangedHandler;
  static ComicSourceUiHandler? uiHandler;

  static void update({
    String? dataPath,
    String? appVersion,
    String? locale,
    String? userAgent,
    Dio? dio,
    VoidCallback? dataChangedHandler,
    ComicSourceUiHandler? uiHandler,
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
    if (uiHandler != null) {
      _Config.uiHandler = uiHandler;
    }
  }

  static CookieJarSql ensureCookieJar() {
    if (dataPath.isEmpty) {
      throw StateError('dataPath must be set before initializing cookies');
    }
    final jar = cookieJar ??= SingleInstanceCookieJar.createInstance(dataPath);
    if (!dio.interceptors.any((e) => e is CookieManagerSql)) {
      dio.interceptors.add(CookieManagerSql(jar));
    }
    return jar;
  }

  static void disposeCookieJar() {
    dio.interceptors.removeWhere((e) => e is CookieManagerSql);
    cookieJar = null;
    SingleInstanceCookieJar.disposeInstance();
  }
}
