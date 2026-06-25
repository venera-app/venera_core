import 'dart:io';

import 'package:dio/dio.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_core/src/logging/log.dart';
import 'package:venera_core/src/utils/list.dart';

class CookieJarSql {
  late Database _db;

  final String path;

  CookieJarSql(this.path) {
    init();
  }

  void init() {
    _db = sqlite3.open(path);
    _db.execute('''
      CREATE TABLE IF NOT EXISTS cookies (
        name TEXT NOT NULL,
        value TEXT NOT NULL,
        domain TEXT NOT NULL,
        path TEXT,
        expires INTEGER,
        secure INTEGER,
        httpOnly INTEGER,
        PRIMARY KEY (name, domain, path)
      );
    ''');
  }

  void saveFromResponse(Uri uri, List<Cookie> cookies) {
    final current = loadForRequest(uri);
    for (final cookie in cookies) {
      final currentCookie = current.firstWhereOrNull(
        (element) =>
            element.name == cookie.name &&
            (cookie.path == null || cookie.path!.startsWith(element.path!)),
      );
      if (currentCookie != null) {
        cookie.domain = currentCookie.domain;
      }
      _db.execute(
        '''
        INSERT OR REPLACE INTO cookies (name, value, domain, path, expires, secure, httpOnly)
        VALUES (?, ?, ?, ?, ?, ?, ?);
      ''',
        [
          cookie.name,
          cookie.value,
          cookie.domain ?? uri.host,
          cookie.path ?? '/',
          cookie.expires?.millisecondsSinceEpoch,
          cookie.secure ? 1 : 0,
          cookie.httpOnly ? 1 : 0,
        ],
      );
    }
  }

  List<Cookie> _loadWithDomain(String domain) {
    final rows = _db.select(
      '''
      SELECT name, value, domain, path, expires, secure, httpOnly
      FROM cookies
      WHERE domain = ?;
    ''',
      [domain],
    );

    return rows
        .map(
          (row) => Cookie(row['name'] as String, row['value'] as String)
            ..domain = row['domain'] as String
            ..path = row['path'] as String
            ..expires = row['expires'] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(row['expires'] as int)
            ..secure = row['secure'] == 1
            ..httpOnly = row['httpOnly'] == 1,
        )
        .toList();
  }

  List<String> _getAcceptedDomains(String host) {
    final acceptedDomains = <String>[host];
    final hostParts = host.split('.');
    for (var i = 0; i < hostParts.length - 1; i++) {
      acceptedDomains.add('.${hostParts.sublist(i).join('.')}');
    }
    return acceptedDomains;
  }

  List<Cookie> loadForRequest(Uri uri) {
    final acceptedDomains = _getAcceptedDomains(uri.host);

    final cookies = <Cookie>[];
    for (final domain in acceptedDomains) {
      cookies.addAll(_loadWithDomain(domain));
    }

    final expires = cookies.where(
      (cookie) =>
          cookie.expires != null && cookie.expires!.isBefore(DateTime.now()),
    );
    for (final cookie in expires) {
      _db.execute(
        '''
        DELETE FROM cookies
        WHERE name = ? AND domain = ? AND path = ?;
      ''',
        [cookie.name, cookie.domain, cookie.path],
      );
    }

    return cookies
        .where(
          (element) =>
              !expires.contains(element) && _checkPathMatch(uri, element.path),
        )
        .toList();
  }

  bool _checkPathMatch(Uri uri, String? cookiePath) {
    if (cookiePath == null) {
      return true;
    }
    if (cookiePath == uri.path) {
      return true;
    }
    if (cookiePath == '/') {
      return true;
    }
    if (cookiePath.endsWith('/')) {
      return uri.path.startsWith(cookiePath);
    }
    return uri.path.startsWith(cookiePath);
  }

  void saveFromResponseCookieHeader(Uri uri, List<String> cookieHeader) {
    final cookies = <Cookie>[];
    for (final header in cookieHeader) {
      try {
        cookies.add(Cookie.fromSetCookieValue(header));
      } catch (_) {
        Log.warning('Network', 'Invalid cookie header: $header');
      }
    }
    saveFromResponse(uri, cookies);
  }

  String loadForRequestCookieHeader(Uri uri) {
    final cookies = loadForRequest(uri);
    final map = <String, Cookie>{};
    for (final cookie in cookies) {
      final current = map[cookie.name];
      if (current == null) {
        map[cookie.name] = cookie;
      } else if (cookie.domain![0] != '.' && current.domain![0] == '.') {
        map[cookie.name] = cookie;
      } else if (cookie.domain!.length > current.domain!.length) {
        map[cookie.name] = cookie;
      }
    }
    return map.entries
        .map((cookie) => '${cookie.value.name}=${cookie.value.value}')
        .join('; ');
  }

  void delete(Uri uri, String name) {
    final acceptedDomains = _getAcceptedDomains(uri.host);
    for (final domain in acceptedDomains) {
      _db.execute(
        '''
        DELETE FROM cookies
        WHERE name = ? AND domain = ? AND path = ?;
      ''',
        [name, domain, uri.path],
      );
    }
  }

  void deleteUri(Uri uri) {
    final acceptedDomains = _getAcceptedDomains(uri.host);
    for (final domain in acceptedDomains) {
      _db.execute(
        '''
        DELETE FROM cookies
        WHERE domain = ?;
      ''',
        [domain],
      );
    }
  }

  void deleteAll() {
    _db.execute('''
      DELETE FROM cookies;
    ''');
  }

  void dispose() {
    _db.close();
  }
}

class SingleInstanceCookieJar extends CookieJarSql {
  factory SingleInstanceCookieJar(String path) =>
      instance ??= SingleInstanceCookieJar._create(path);

  SingleInstanceCookieJar._create(super.path);

  static SingleInstanceCookieJar? instance;

  static SingleInstanceCookieJar createInstance(String dataPath) {
    instance ??= SingleInstanceCookieJar(
      '$dataPath${Platform.pathSeparator}cookie.db',
    );
    return instance!;
  }

  static void disposeInstance() {
    instance?.dispose();
    instance = null;
  }
}

class CookieManagerSql extends Interceptor {
  final CookieJarSql cookieJar;

  CookieManagerSql(this.cookieJar);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    var cookies = cookieJar.loadForRequestCookieHeader(options.uri);
    if (cookies.isNotEmpty) {
      if (options.headers['cookie'] != null) {
        cookies = "${options.headers['cookie']}; $cookies";
      }
      options.headers['cookie'] = cookies;
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    cookieJar.saveFromResponseCookieHeader(
      response.requestOptions.uri,
      response.headers['set-cookie'] ?? [],
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(err);
  }
}
