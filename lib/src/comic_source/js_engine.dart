part of 'comic_source.dart';

typedef VoidCallback = void Function();

class JSAutoFreeFunction {
  final JSInvokable func;

  JSAutoFreeFunction(this.func) {
    func.dup();
    finalizer.attach(this, func);
  }

  dynamic call(List<dynamic> args) => func(args);

  static final finalizer = Finalizer<JSInvokable>((func) {
    func.destroy();
  });
}

class JsEngine with _JSEngineApi {
  static JsEngine? _cache;

  factory JsEngine() => _cache ??= JsEngine._();

  JsEngine._();

  FlutterQjs? _engine;
  Future<void>? _initializing;

  static void reset() {
    _cache?.dispose();
    _cache = null;
  }

  Future<void> init() async {
    if (_engine != null) {
      return;
    }
    final initializing = _initializing;
    if (initializing != null) {
      return initializing;
    }
    final future = _init();
    _initializing = future;
    try {
      await future;
    } finally {
      _initializing = null;
    }
  }

  Future<void> ensureInit() => init();

  Future<void> _init() async {
    _engine = FlutterQjs();
    unawaited(_engine!.dispatch());

    final setGlobalFunc = _engine!.evaluate(
      '(key, value) => { this[key] = value; }',
    );
    (setGlobalFunc as JSInvokable)(['sendMessage', _messageReceiver]);
    setGlobalFunc(['appVersion', _Config.appVersion]);
    setGlobalFunc.free();

    _engine!.evaluate(_initJs, name: '<init>');
  }

  dynamic runCode(String js, [String? name]) {
    final engine = _engine;
    if (engine == null) {
      throw StateError('JsEngine is not initialized. Call init() first.');
    }
    return engine.evaluate(js, name: name);
  }

  Object? _messageReceiver(dynamic message) {
    if (message is! Map) return null;
    final map = Map<String, dynamic>.from(message);
    switch (map['method']) {
      case 'log':
        Log.error(map['title']?.toString() ?? 'JavaScript', map['content']);
        return null;
      case 'load_data':
        final source = ComicSource.find(map['key']);
        return source?.data[map['data_key']];
      case 'save_data':
        final source = ComicSource.find(map['key']);
        if (source == null) return null;
        final dataKey = map['data_key'];
        if (dataKey == 'setting') {
          throw StateError('setting is not allowed to be saved');
        }
        source.data[dataKey] = map['data'];
        unawaited(source.saveData());
        return null;
      case 'delete_data':
        final source = ComicSource.find(map['key']);
        source?.data.remove(map['data_key']);
        if (source != null) unawaited(source.saveData());
        return null;
      case 'load_setting':
        final source = ComicSource.find(map['key']);
        final settingKey = map['setting_key'];
        return source?.data['settings']?[settingKey] ??
            source?.settings?[settingKey]?['default'] ??
            (throw StateError('Setting not found: $settingKey'));
      case 'isLogged':
        return ComicSource.find(map['key'])?.isLogged ?? false;
      case 'delay':
        return Future.delayed(Duration(milliseconds: map['time'] ?? 0));
      case 'http':
        return _http(map);
      case 'html':
        return handleHtmlCallback(map);
      case 'convert':
        return _convert(map);
      case 'random':
        return _random(map['min'] ?? 0, map['max'] ?? 1, map['type'] ?? 'int');
      case 'cookie':
        return handleCookieCallback(map);
      case 'uuid':
        return const Uuid().v1();
      case 'getLocale':
        return _Config.locale;
      case 'getPlatform':
        return Platform.operatingSystem;
      case 'compute':
        return _compute(map);
      case 'UI':
        return _ui(map);
      case 'setClipboard':
        final handler = _uiHandlerOrException(map);
        if (handler is Exception) return handler;
        return (handler as ComicSourceUiHandler).setClipboard(
          map['text']?.toString() ?? '',
        );
      case 'getClipboard':
        final handler = _uiHandlerOrException(map);
        if (handler is Exception) return handler;
        return (handler as ComicSourceUiHandler).getClipboard();
      default:
        return _missingMessageHandler(map);
    }
  }

  Object _missingMessageHandler(Map<String, dynamic> message) {
    return Exception(
      'No JavaScript message handler provided for method: ${message['method']}',
    );
  }

  dynamic _ui(Map<String, dynamic> message) {
    final handler = _uiHandlerOrException(message);
    if (handler is Exception) return handler;
    if (handler is! ComicSourceUiHandler) {
      return _missingMessageHandler(message);
    }

    switch (message['function']) {
      case 'showMessage':
        final content = message['message']?.toString() ?? '';
        if (content.isEmpty) return null;
        return handler.showMessage(content);
      case 'showDialog':
        return handler.showDialog(
          title: message['title']?.toString(),
          content: message['content']?.toString(),
          actions: _dialogActions(message['actions']),
        );
      case 'launchUrl':
        final url = message['url']?.toString() ?? '';
        if (url.isEmpty) return null;
        return handler.launchUrl(url);
      case 'showLoading':
        final onCancel = message['onCancel'];
        if (onCancel != null && onCancel is! JSInvokable) return null;
        return handler.showLoading(
          onCancel: onCancel == null ? null : JSAutoFreeFunction(onCancel),
        );
      case 'cancelLoading':
        final id = message['id'];
        if (id is! int) return null;
        return handler.cancelLoading(id);
      case 'showInputDialog':
        final title = message['title'];
        final validator = message['validator'];
        if (title is! String) return null;
        if (validator != null && validator is! JSInvokable) return null;
        return handler.showInputDialog(
          title: title,
          validator: validator == null ? null : JSAutoFreeFunction(validator),
          image: message['image'],
        );
      case 'showSelectDialog':
        final title = message['title'];
        final options = message['options'];
        final initialIndex = message['initialIndex'];
        if (title is! String) return null;
        if (options is! List) return null;
        if (initialIndex != null && initialIndex is! int) return null;
        return handler.showSelectDialog(
          title: title,
          options: options.whereType<String>().toList(),
          initialIndex: initialIndex,
        );
      default:
        return Exception(
          'No JavaScript UI handler provided for function: '
          '${message['function']}',
        );
    }
  }

  Object? _uiHandlerOrException(Map<String, dynamic> message) {
    return _Config.uiHandler ??
        Exception(
          'No JavaScript UI handler provided for method: ${message['method']}',
        );
  }

  List<ComicSourceDialogAction> _dialogActions(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((action) {
          final callback = action['callback'];
          if (callback is! JSInvokable) return null;
          return ComicSourceDialogAction(
            text: action['text']?.toString() ?? '',
            style: action['style']?.toString() ?? 'text',
            callback: JSAutoFreeFunction(callback),
          );
        })
        .whereType<ComicSourceDialogAction>()
        .toList();
  }

  Future<Map<String, dynamic>> _http(Map<String, dynamic> req) async {
    Response<List<int>>? response;
    Object? error;
    dynamic body;
    final headers = <String, String>{};

    try {
      final url = req['url'].toString();
      final method = (req['http_method'] ?? 'GET').toString().toUpperCase();
      final requestHeaders = Map<String, dynamic>.from(req['headers'] ?? {});
      final hasUserAgent = requestHeaders.keys.any(
        (key) => key.toString().toLowerCase() == 'user-agent',
      );
      if (!hasUserAgent) {
        requestHeaders[HttpHeaders.userAgentHeader] = _Config.userAgent;
      }
      final data = req['data'];
      final requestData = data == null || data is String ? data : _bytes(data);
      final extra = req['extra'] is Map
          ? Map<String, dynamic>.from(req['extra'])
          : null;
      response = await _Config.dio.request<List<int>>(
        url,
        data: requestData,
        options: Options(
          method: method,
          headers: requestHeaders,
          extra: extra,
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
        ),
      );
      response.headers.forEach((name, values) {
        headers[name] = values.join(',');
      });
      final bytes = Uint8List.fromList(response.data ?? const <int>[]);
      body = req['bytes'] == true
          ? bytes
          : utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      error = e;
    }

    return {
      'status': response?.statusCode,
      'headers': headers,
      'body': body,
      'error': error?.toString(),
    };
  }

  Future<dynamic> _compute(Map<String, dynamic> message) async {
    final func = message['function'];
    final args = message['args'];
    if (func is JSInvokable) {
      func.free();
      throw StateError('Function must be a string');
    }
    if (func is! String) {
      throw StateError('Function must be a string');
    }
    if (args != null && args is! List) {
      throw StateError('Args must be a list');
    }
    return Future.microtask(() {
      final jsFunc = runCode('($func)');
      if (jsFunc is! JSInvokable) {
        throw StateError('The provided code does not evaluate to a function.');
      }
      try {
        return jsFunc.invoke(args ?? []);
      } finally {
        jsFunc.free();
      }
    });
  }

  void dispose() {
    _engine?.close();
    _engine?.port.close();
    _engine = null;
  }
}

mixin class _JSEngineApi {
  final _documents = <int, DocumentWrapper>{};
  final _cookies = <String, List<Cookie>>{};

  Object? handleHtmlCallback(Map<String, dynamic> data) {
    switch (data['function']) {
      case 'parse':
        if (_documents.length > 8) {
          _documents.remove(_documents.keys.first);
        }
        _documents[data['key']] = DocumentWrapper.parse(data['data']);
        return null;
      case 'querySelector':
        return _documents[data['key']]!.querySelector(data['query']);
      case 'querySelectorAll':
        return _documents[data['key']]!.querySelectorAll(data['query']);
      case 'getText':
        return _documents[data['doc']]!.elementGetText(data['key']);
      case 'getAttributes':
        return _documents[data['doc']]!.elementGetAttributes(data['key']);
      case 'dom_querySelector':
        return _documents[data['doc']]!.elementQuerySelector(
          data['key'],
          data['query'],
        );
      case 'dom_querySelectorAll':
        return _documents[data['doc']]!.elementQuerySelectorAll(
          data['key'],
          data['query'],
        );
      case 'getChildren':
        return _documents[data['doc']]!.elementGetChildren(data['key']);
      case 'getNodes':
        return _documents[data['doc']]!.elementGetNodes(data['key']);
      case 'getInnerHTML':
        return _documents[data['doc']]!.elementGetInnerHTML(data['key']);
      case 'getParent':
        return _documents[data['doc']]!.elementGetParent(data['key']);
      case 'node_text':
        return _documents[data['doc']]!.nodeGetText(data['key']);
      case 'node_type':
        return _documents[data['doc']]!.nodeType(data['key']);
      case 'node_to_element':
        return _documents[data['doc']]!.nodeToElement(data['key']);
      case 'dispose':
        _documents.remove(data['key']);
        return null;
      case 'getClassNames':
        return _documents[data['doc']]!.getClassNames(data['key']);
      case 'getId':
        return _documents[data['doc']]!.getId(data['key']);
      case 'getLocalName':
        return _documents[data['doc']]!.getLocalName(data['key']);
      case 'getElementById':
        return _documents[data['key']]!.getElementById(data['id']);
      case 'getPreviousSibling':
        return _documents[data['doc']]!.getPreviousSibling(data['key']);
      case 'getNextSibling':
        return _documents[data['doc']]!.getNextSibling(data['key']);
    }
    return null;
  }

  dynamic handleCookieCallback(Map<String, dynamic> data) {
    final url = Uri.parse(data['url']);
    final host = url.host;
    switch (data['function']) {
      case 'set':
        final list = _cookies.putIfAbsent(host, () => []);
        for (final item in data['cookies'] as List) {
          final map = Map<String, dynamic>.from(item);
          list.removeWhere((cookie) => cookie.name == map['name']);
          final cookie = Cookie(map['name'], map['value']);
          if (map['domain'] != null) cookie.domain = map['domain'];
          if (map['path'] != null) cookie.path = map['path'];
          list.add(cookie);
        }
        return null;
      case 'get':
        return (_cookies[host] ?? const <Cookie>[])
            .map(
              (cookie) => {
                'name': cookie.name,
                'value': cookie.value,
                'domain': cookie.domain,
                'path': cookie.path,
                'expires': cookie.expires,
                'max-age': cookie.maxAge,
                'secure': cookie.secure,
                'httpOnly': cookie.httpOnly,
                'session': cookie.expires == null,
              },
            )
            .toList();
      case 'delete':
        _cookies.remove(host);
        return null;
    }
  }

  Object? _convert(Map<String, dynamic> data) {
    final type = data['type'] as String;
    final value = data['value'];
    final isEncode = data['isEncode'] == true;
    try {
      switch (type) {
        case 'utf8':
          return isEncode ? utf8.encode(value) : utf8.decode(_bytes(value));
        case 'gbk':
          const codec = GbkCodec();
          return isEncode
              ? Uint8List.fromList(codec.encode(value))
              : codec.decode(_bytes(value));
        case 'base64':
          return isEncode ? base64Encode(_bytes(value)) : base64Decode(value);
        case 'md5':
          return Uint8List.fromList(md5.convert(_bytes(value)).bytes);
        case 'sha1':
          return Uint8List.fromList(sha1.convert(_bytes(value)).bytes);
        case 'sha256':
          return Uint8List.fromList(sha256.convert(_bytes(value)).bytes);
        case 'sha512':
          return Uint8List.fromList(sha512.convert(_bytes(value)).bytes);
        case 'hmac':
          final hmac = Hmac(switch (data['hash']) {
            'md5' => md5,
            'sha1' => sha1,
            'sha256' => sha256,
            'sha512' => sha512,
            final hash => throw UnsupportedError('Unsupported hash: $hash'),
          }, _bytes(data['key']));
          final digest = hmac.convert(_bytes(value));
          return data['isString'] == true
              ? digest.toString()
              : Uint8List.fromList(digest.bytes);
        case 'aes-ecb':
          return _blockCipher(
            ECBBlockCipher(AESEngine()),
            isEncode,
            KeyParameter(_bytes(data['key'])),
            _bytes(value),
          );
        case 'aes-cbc':
          return _blockCipher(
            CBCBlockCipher(AESEngine()),
            isEncode,
            ParametersWithIV(
              KeyParameter(_bytes(data['key'])),
              _bytes(data['iv']),
            ),
            _bytes(value),
          );
        case 'aes-cfb':
          return _blockCipher(
            CFBBlockCipher(AESEngine(), data['blockSize']),
            isEncode,
            ParametersWithIV(
              KeyParameter(_bytes(data['key'])),
              _bytes(data['iv']),
            ),
            _bytes(value),
          );
        case 'aes-ofb':
          return _blockCipher(
            OFBBlockCipher(AESEngine(), data['blockSize']),
            isEncode,
            ParametersWithIV(
              KeyParameter(_bytes(data['key'])),
              _bytes(data['iv']),
            ),
            _bytes(value),
          );
        case 'rsa':
          if (!isEncode) {
            final cipher = PKCS1Encoding(RSAEngine());
            cipher.init(
              false,
              PrivateKeyParameter<RSAPrivateKey>(_parsePrivateKey(data['key'])),
            );
            return _processInBlocks(cipher, _bytes(value));
          }
          return null;
        default:
          return value;
      }
    } catch (e) {
      Log.error('JS Engine', 'Failed to convert $type: $e');
      return null;
    }
  }

  RSAPrivateKey _parsePrivateKey(String privateKeyString) {
    var parser = ASN1Parser(base64Decode(privateKeyString));
    final topLevelSeq = parser.nextObject() as ASN1Sequence;
    final privateKey = topLevelSeq.elements![2];

    parser = ASN1Parser(privateKey.valueBytes!);
    final pkSeq = parser.nextObject() as ASN1Sequence;

    final modulus = pkSeq.elements![1] as ASN1Integer;
    final privateExponent = pkSeq.elements![3] as ASN1Integer;
    final p = pkSeq.elements![4] as ASN1Integer;
    final q = pkSeq.elements![5] as ASN1Integer;

    return RSAPrivateKey(
      modulus.integer!,
      privateExponent.integer!,
      p.integer!,
      q.integer!,
    );
  }

  Uint8List _processInBlocks(AsymmetricBlockCipher engine, Uint8List input) {
    final numBlocks =
        input.length ~/ engine.inputBlockSize +
        ((input.length % engine.inputBlockSize != 0) ? 1 : 0);
    final output = Uint8List(numBlocks * engine.outputBlockSize);
    var inputOffset = 0;
    var outputOffset = 0;
    while (inputOffset < input.length) {
      final chunkSize = (inputOffset + engine.inputBlockSize <= input.length)
          ? engine.inputBlockSize
          : input.length - inputOffset;
      outputOffset += engine.processBlock(
        input,
        inputOffset,
        chunkSize,
        output,
        outputOffset,
      );
      inputOffset += chunkSize;
    }
    return output.length == outputOffset
        ? output
        : output.sublist(0, outputOffset);
  }

  num _random(num min, num max, String type) {
    if (type == 'double') {
      return min + (max - min) * math.Random().nextDouble();
    }
    return (min + (max - min) * math.Random().nextDouble()).toInt();
  }
}

Uint8List _blockCipher(
  BlockCipher cipher,
  bool forEncryption,
  CipherParameters params,
  Uint8List value,
) {
  cipher.init(forEncryption, params);
  var offset = 0;
  final result = Uint8List(value.length);
  while (offset < value.length) {
    offset += cipher.processBlock(value, offset, result, offset);
  }
  return result;
}

Uint8List _bytes(dynamic value) {
  if (value is Uint8List) return value;
  if (value is List<int>) return Uint8List.fromList(value);
  if (value is List) return Uint8List.fromList(value.cast<int>());
  if (value is String) return Uint8List.fromList(utf8.encode(value));
  throw ArgumentError('Expected bytes or string, got ${value.runtimeType}');
}

class DocumentWrapper {
  final dom.Document doc;

  DocumentWrapper.parse(String doc) : doc = html.parse(doc);

  final elements = <dom.Element>[];
  final nodes = <dom.Node>[];

  int? querySelector(String query) {
    final element = doc.querySelector(query);
    if (element == null) return null;
    elements.add(element);
    return elements.length - 1;
  }

  List<int> querySelectorAll(String query) {
    final res = doc.querySelectorAll(query);
    final keys = <int>[];
    for (final element in res) {
      elements.add(element);
      keys.add(elements.length - 1);
    }
    return keys;
  }

  String? elementGetText(int key) => elements[key].text;

  Map<String, String> elementGetAttributes(int key) {
    return elements[key].attributes.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  String? elementGetInnerHTML(int key) => elements[key].innerHtml;

  int? elementGetParent(int key) {
    final res = elements[key].parent;
    if (res == null) return null;
    elements.add(res);
    return elements.length - 1;
  }

  int? elementQuerySelector(int key, String query) {
    final res = elements[key].querySelector(query);
    if (res == null) return null;
    elements.add(res);
    return elements.length - 1;
  }

  List<int> elementQuerySelectorAll(int key, String query) {
    final res = elements[key].querySelectorAll(query);
    final keys = <int>[];
    for (final element in res) {
      elements.add(element);
      keys.add(elements.length - 1);
    }
    return keys;
  }

  List<int> elementGetChildren(int key) {
    final keys = <int>[];
    for (final element in elements[key].children) {
      elements.add(element);
      keys.add(elements.length - 1);
    }
    return keys;
  }

  List<int> elementGetNodes(int key) {
    final keys = <int>[];
    for (final node in elements[key].nodes) {
      nodes.add(node);
      keys.add(nodes.length - 1);
    }
    return keys;
  }

  String? nodeGetText(int key) => nodes[key].text;

  String nodeType(int key) {
    return switch (nodes[key].nodeType) {
      dom.Node.ELEMENT_NODE => 'element',
      dom.Node.TEXT_NODE => 'text',
      dom.Node.COMMENT_NODE => 'comment',
      dom.Node.DOCUMENT_NODE => 'document',
      _ => 'unknown',
    };
  }

  int? nodeToElement(int key) {
    if (nodes[key] is dom.Element) {
      elements.add(nodes[key] as dom.Element);
      return elements.length - 1;
    }
    return null;
  }

  List<String> getClassNames(int key) => elements[key].classes.toList();

  String? getId(int key) => elements[key].id;

  String? getLocalName(int key) => elements[key].localName;

  int? getElementById(String id) {
    final element = doc.getElementById(id);
    if (element == null) return null;
    elements.add(element);
    return elements.length - 1;
  }

  int? getPreviousSibling(int key) {
    final res = elements[key].previousElementSibling;
    if (res == null) return null;
    elements.add(res);
    return elements.length - 1;
  }

  int? getNextSibling(int key) {
    final res = elements[key].nextElementSibling;
    if (res == null) return null;
    elements.add(res);
    return elements.length - 1;
  }
}
