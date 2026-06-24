library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dart_qjs/dart_qjs.dart';
import 'package:dio/dio.dart';
import 'package:enough_convert/enough_convert.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asn1/asn1_parser.dart';
import 'package:pointycastle/asn1/primitives/asn1_integer.dart';
import 'package:pointycastle/asn1/primitives/asn1_sequence.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/pkcs1.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/block/modes/cfb.dart';
import 'package:pointycastle/block/modes/ecb.dart';
import 'package:pointycastle/block/modes/ofb.dart';
import 'package:uuid/uuid.dart';
import 'package:venera_core/venera_core.dart';
import 'package:venera_core/src/utils/file_path.dart';
import 'package:venera_core/src/utils/list.dart';

part 'js_engine.dart';
part 'category.dart';

part 'favorites.dart';

part 'parser.dart';

part 'models/account.dart';
part 'models/category_comics.dart';
part 'models/explore.dart';
part 'models/search.dart';

part 'types.dart';
part 'config.dart';
part 'init_js.dart';

class ComicSourceManager with ChangeNotifier {
  final List<ComicSource> _sources = [];

  static ComicSourceManager? _instance;

  ComicSourceManager._create();

  factory ComicSourceManager() => _instance ??= ComicSourceManager._create();

  List<ComicSource> all() => List.from(_sources);

  ComicSource? find(String key) =>
      _sources.firstWhereOrNull((element) => element.key == key);

  ComicSource? fromIntKey(int key) =>
      _sources.firstWhereOrNull((element) => element.key.hashCode == key);

  Future<void> init({
    String? dataPath,
    String? appVersion,
    String? locale,
    String? userAgent,
    Dio? dio,
    VoidCallback? dataChangedHandler,
  }) async {
    _Config.update(
      dataPath: dataPath,
      appVersion: appVersion,
      locale: locale,
      userAgent: userAgent,
      dio: dio,
      dataChangedHandler: dataChangedHandler,
    );
    await JsEngine().init();
    final path = FilePath.join(_Config.dataPath, "comic_source");
    if (!(await Directory(path).exists())) {
      Directory(path).create();
      return;
    }
    await for (var entity in Directory(path).list()) {
      if (entity is File && entity.path.endsWith(".js")) {
        try {
          var source = await ComicSourceParser().parse(
            await entity.readAsString(),
            entity.absolute.path,
          );
          _sources.add(source);
        } catch (e, s) {
          Log.error("ComicSource", "$e\n$s");
        }
      }
    }
  }

  Future reload() async {
    _sources.clear();
    JsEngine().runCode("ComicSource.sources = {};");
    await init();
    notifyListeners();
  }

  void add(ComicSource source) {
    _sources.add(source);
    notifyListeners();
  }

  void remove(String key) {
    _sources.removeWhere((element) => element.key == key);
    notifyListeners();
  }

  bool get isEmpty => _sources.isEmpty;

  /// Key is the source key, value is the version.
  final _availableUpdates = <String, String>{};

  void updateAvailableUpdates(Map<String, String> updates) {
    _availableUpdates.addAll(updates);
    notifyListeners();
  }

  Map<String, String> get availableUpdates => Map.from(_availableUpdates);

  void notifyStateChange() {
    notifyListeners();
  }
}

class ComicSource {
  static List<ComicSource> all() => ComicSourceManager().all();

  static ComicSource? find(String key) => ComicSourceManager().find(key);

  static ComicSource? fromIntKey(int key) =>
      ComicSourceManager().fromIntKey(key);

  static bool get isEmpty => ComicSourceManager().isEmpty;

  /// Name of this source.
  final String name;

  /// Identifier of this source.
  final String key;

  int get intKey {
    return key.hashCode;
  }

  /// Account config.
  final AccountConfig? account;

  /// Category data used to build a static category tags page.
  final CategoryData? categoryData;

  /// Category comics data used to build a comics page with a category tag.
  final CategoryComicsData? categoryComicsData;

  /// Favorite data used to build favorite page.
  final FavoriteData? favoriteData;

  /// Explore pages.
  final List<ExplorePageData> explorePages;

  /// Search page.
  final SearchPageData? searchPageData;

  /// Load comic info.
  final LoadComicFunc? loadComicInfo;

  final ComicThumbnailLoader? loadComicThumbnail;

  /// Load comic pages.
  final LoadComicPagesFunc? loadComicPages;

  final GetImageLoadingConfigFunc? getImageLoadingConfig;

  final Map<String, dynamic> Function(String imageKey)?
  getThumbnailLoadingConfig;

  var data = <String, dynamic>{};

  bool get isLogged => data["account"] != null;

  final String filePath;

  final String url;

  final String version;

  final CommentsLoader? commentsLoader;

  final SendCommentFunc? sendCommentFunc;

  final ChapterCommentsLoader? chapterCommentsLoader;

  final SendChapterCommentFunc? sendChapterCommentFunc;

  final RegExp? idMatcher;

  final LikeOrUnlikeComicFunc? likeOrUnlikeComic;

  final VoteCommentFunc? voteCommentFunc;

  final LikeCommentFunc? likeCommentFunc;

  final Map<String, Map<String, dynamic>>? settings;

  final Map<String, Map<String, String>>? translations;

  final HandleClickTagEvent? handleClickTagEvent;

  /// Callback when a tag suggestion is selected in search.
  final TagSuggestionSelectFunc? onTagSuggestionSelected;

  final LinkHandler? linkHandler;

  final bool enableTagsSuggestions;

  final bool enableTagsTranslate;

  final StarRatingFunc? starRatingFunc;

  final ArchiveDownloader? archiveDownloader;

  Future<void> loadData() async {
    var file = File(
      FilePath.join(_Config.dataPath, "comic_source", "$key.data"),
    );
    if (await file.exists()) {
      data = Map.from(jsonDecode(await file.readAsString()));
    }
  }

  bool _isSaving = false;
  bool _haveWaitingTask = false;

  Future<void> saveData() async {
    if (_haveWaitingTask) return;
    while (_isSaving) {
      _haveWaitingTask = true;
      await Future.delayed(const Duration(milliseconds: 20));
      _haveWaitingTask = false;
    }
    _isSaving = true;
    var file = File(
      FilePath.join(_Config.dataPath, "comic_source", "$key.data"),
    );
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    await file.writeAsString(jsonEncode(data));
    _isSaving = false;
    _Config.dataChangedHandler?.call();
  }

  Future<bool> reLogin() async {
    if (data["account"] == null) {
      return false;
    }
    final List accountData = data["account"];
    var res = await account!.login!(accountData[0], accountData[1]);
    if (res.error) {
      Log.error("Failed to re-login", res.errorMessage ?? "Error");
    }
    return !res.error;
  }

  /// Get settings dynamically from JavaScript source.
  /// This allows sources to use getters for dynamic settings that can change at runtime.
  Map<String, Map<String, dynamic>>? getSettingsDynamic() {
    try {
      var value = JsEngine().runCode("ComicSource.sources.$key.settings");
      if (value is Map) {
        var newMap = <String, Map<String, dynamic>>{};
        for (var e in value.entries) {
          if (e.key is! String) {
            continue;
          }
          var v = <String, dynamic>{};
          for (var e2 in e.value.entries) {
            if (e2.key is! String) {
              continue;
            }
            var v2 = e2.value;
            if (v2 is JSInvokable) {
              v2 = JSAutoFreeFunction(v2);
            }
            v[e2.key] = v2;
          }
          newMap[e.key] = v;
        }
        return newMap;
      }
      return null;
    } catch (e) {
      Log.error("ComicSource", "Failed to get dynamic settings: $e");
      return settings;
    }
  }

  ComicSource(
    this.name,
    this.key,
    this.account,
    this.categoryData,
    this.categoryComicsData,
    this.favoriteData,
    this.explorePages,
    this.searchPageData,
    this.settings,
    this.loadComicInfo,
    this.loadComicThumbnail,
    this.loadComicPages,
    this.getImageLoadingConfig,
    this.getThumbnailLoadingConfig,
    this.filePath,
    this.url,
    this.version,
    this.commentsLoader,
    this.sendCommentFunc,
    this.chapterCommentsLoader,
    this.sendChapterCommentFunc,
    this.likeOrUnlikeComic,
    this.voteCommentFunc,
    this.likeCommentFunc,
    this.idMatcher,
    this.translations,
    this.handleClickTagEvent,
    this.onTagSuggestionSelected,
    this.linkHandler,
    this.enableTagsSuggestions,
    this.enableTagsTranslate,
    this.starRatingFunc,
    this.archiveDownloader,
  );
}
