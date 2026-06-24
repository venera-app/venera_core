import 'dart:io';

import 'package:test/test.dart';
import 'package:venera_core/venera_core.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('venera_core_test_');
    await ComicSourceManager().init(
      dataPath: tempDir.path,
      appVersion: '2.0.0',
      locale: 'en_US',
      userAgent: 'test-agent',
    );
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('compareSemVer', () {
    test('orders stable, prerelease and hotfix versions', () {
      expect(compareSemVer('1.2.4', '1.2.3'), isTrue);
      expect(compareSemVer('1.2.3', '1.2.3'), isFalse);
      expect(compareSemVer('1.2.3', '1.2.4'), isFalse);
      expect(compareSemVer('1.2.3', '1.2.3-beta'), isTrue);
      expect(compareSemVer('1.2.3-hotfix', '1.2.3'), isTrue);
      expect(compareSemVer('1.2.3-beta', '1.2.3'), isFalse);
    });
  });

  group('ComicSourceParser', () {
    test('rejects invalid source content', () async {
      await expectLater(
        ComicSourceParser().parse('const source = {}', 'invalid.js'),
        throwsA(
          isA<ComicSourceParseException>().having(
            (e) => e.toString(),
            'message',
            'Invalid Content',
          ),
        ),
      );
    });

    test('rejects keys with unsupported characters', () async {
      await expectLater(
        ComicSourceParser().parse(
          _sourceScript(
            key: 'bad-key',
            name: 'Bad Key Source',
            body: '''
              comic = {
                loadInfo: () => ({
                  title: 'x',
                  cover: 'cover',
                  tags: {},
                }),
                loadEp: () => ({ images: [] }),
              }
            ''',
          ),
          'bad_key.js',
        ),
        throwsA(
          isA<ComicSourceParseException>().having(
            (e) => e.toString(),
            'message',
            'key bad-key is invalid',
          ),
        ),
      );
    });

    test('rejects sources requiring a newer app version', () async {
      await expectLater(
        ComicSourceParser().parse(
          _sourceScript(
            key: 'requires_new_app',
            minAppVersion: '9.0.0',
            body: '''
              comic = {
                loadInfo: () => ({
                  title: 'x',
                  cover: 'cover',
                  tags: {},
                }),
                loadEp: () => ({ images: [] }),
              }
            ''',
          ),
          'requires_new_app.js',
        ),
        throwsA(
          isA<ComicSourceParseException>().having(
            (e) => e.toString(),
            'message',
            'minAppVersion 9.0.0 is required',
          ),
        ),
      );
    });

    test('parses metadata, category, search options and settings', () async {
      final source = await ComicSourceParser().parse(
        _sourceScript(
          key: 'metadata_source',
          name: 'Metadata Source',
          url: 'https://example.test',
          version: '1.2.3',
          body: '''
            settings = {
              enabled: {
                type: 'switch',
                default: true,
              },
            }

            category = {
              title: 'Browse',
              enableRankingPage: true,
              parts: [
                {
                  name: 'Genres',
                  type: 'fixed',
                  categories: [
                    { label: 'Action', target: { page: 'search', attributes: { text: 'action' } } },
                    { label: 'Drama', target: 'category:drama@popular' },
                  ],
                },
              ],
            }

            search = {
              optionList: [
                {
                  label: 'Sort',
                  type: 'select',
                  default: 'latest',
                  options: ['latest-Latest', 'popular-Most Popular'],
                },
              ],
              load: (keyword, option, page) => ({ comics: [], maxPage: page }),
            }

            comic = {
              idMatch: 'comic/(\\\\w+)',
              onClickTag: (namespace, tag) => ({ action: 'search', keyword: namespace + ':' + tag }),
              loadInfo: () => ({
                title: 'x',
                cover: 'cover',
                tags: {},
              }),
              loadEp: () => ({ images: [] }),
            }
          ''',
        ),
        'metadata_source.js',
      );

      expect(source.name, 'Metadata Source');
      expect(source.key, 'metadata_source');
      expect(source.url, 'https://example.test');
      expect(source.version, '1.2.3');
      expect(source.settings?['enabled']?['default'], isTrue);
      expect(source.idMatcher?.hasMatch('comic/abc'), isTrue);

      final category = source.categoryData!;
      expect(category.title, 'Browse');
      expect(category.enableRankingPage, isTrue);
      expect(category.categories, hasLength(1));
      expect(category.categories.first.categories, hasLength(2));
      expect(category.categories.first.categories.first.target.page, 'search');
      expect(category.categories.first.categories.first.target.attributes, {
        'text': 'action',
      });
      expect(category.categories.first.categories.last.target.page, 'category');
      expect(category.categories.first.categories.last.target.attributes, {
        'category': 'drama',
        'param': 'popular',
      });

      final search = source.searchPageData!;
      expect(search.searchOptions, hasLength(1));
      expect(search.searchOptions!.first.defaultValue, '"latest"');
      expect(search.searchOptions!.first.options, {
        'latest': 'Latest',
        'popular': 'Most Popular',
      });

      final target = source.handleClickTagEvent!('artist', 'alice')!;
      expect(target.page, 'search');
      expect(target.attributes, {'text': 'artist:alice'});
    });

    test('maps JS search and comic callbacks into Dart models', () async {
      final source = await ComicSourceParser().parse(
        _sourceScript(
          key: 'callback_source',
          body: '''
            search = {
              load: (keyword, option, page) => ({
                maxPage: 7,
                comics: [
                  {
                    title: keyword + '-' + option[0],
                    cover: 'cover-' + page,
                    id: 'comic-' + page,
                    subtitle: 'sub',
                    tags: ['tag'],
                    description: 'desc',
                    maxPage: 4,
                    language: 'en',
                    stars: 4.5,
                  },
                ],
              }),
            }

            comic = {
              loadInfo: (id) => ({
                title: 'Title ' + id,
                subtitle: 'Subtitle',
                cover: 'cover',
                description: 'description',
                tags: {
                  genre: ['Action'],
                },
                chapters: {
                  groups: [
                    {
                      title: 'Main',
                      chapters: [
                        { title: 'Chapter 1', id: 'ep1' },
                      ],
                    },
                  ],
                },
                thumbnails: ['t1'],
                recommend: [
                  { title: 'Rec', cover: 'rc', id: 'rec' },
                ],
                isFavorite: true,
                isLiked: false,
                likesCount: 12,
                commentCount: 3,
                uploader: 'Uploader',
                uploadTime: '2024-01-01',
                updateTime: '2024-01-02',
                url: 'https://example.test/comic/' + id,
                stars: 3.5,
                maxPage: 2,
                comments: [
                  { userName: 'Alice', content: 'Nice', id: 'c1', time: 1700000000 },
                ],
              }),
              loadEp: (id, ep) => ({
                images: [id + '-' + ep + '-1', id + '-' + ep + '-2'],
              }),
              loadThumbnails: (id, next) => ({
                thumbnails: [id + '-' + (next || 'first')],
                next: 'next-page',
              }),
              onImageLoad: (imageKey, comicId, epId) => ({
                url: 'https://img.test/' + imageKey,
                headers: { referer: comicId + '/' + epId },
              }),
              onThumbnailLoad: (imageKey) => ({
                url: 'https://thumb.test/' + imageKey,
              }),
            }
          ''',
        ),
        'callback_source.js',
      );

      final searchResult = await source.searchPageData!.loadPage!(
        'keyword',
        2,
        ['latest'],
      );
      expect(searchResult.error, isFalse);
      expect(searchResult.subData, 7);
      expect(searchResult.data.single.title, 'keyword-latest');
      expect(searchResult.data.single.cover, 'cover-2');
      expect(searchResult.data.single.sourceKey, 'callback_source');
      expect(searchResult.data.single.tags, ['tag']);
      expect(searchResult.data.single.stars, 4.5);

      final detailsResult = await source.loadComicInfo!('abc');
      expect(detailsResult.error, isFalse);
      final details = detailsResult.data;
      expect(details.title, 'Title abc');
      expect(details.comicId, 'abc');
      expect(details.sourceKey, 'callback_source');
      expect(details.tags, {
        'genre': ['Action'],
      });
      expect(details.recommend!.single.sourceKey, 'callback_source');
      expect(details.comments!.single.userName, 'Alice');
      expect(details.comments!.single.time, '2023-11-15 06:13:20');

      final pagesResult = await source.loadComicPages!('abc', 'ep1');
      expect(pagesResult.error, isFalse);
      expect(pagesResult.data, ['abc-ep1-1', 'abc-ep1-2']);

      final thumbnailsResult = await source.loadComicThumbnail!('abc', null);
      expect(thumbnailsResult.error, isFalse);
      expect(thumbnailsResult.data, ['abc-first']);
      expect(thumbnailsResult.subData, 'next-page');

      expect(await source.getImageLoadingConfig!('img1', 'abc', 'ep1'), {
        'url': 'https://img.test/img1',
        'headers': {'referer': 'abc/ep1'},
      });
      expect(source.getThumbnailLoadingConfig!('thumb1'), {
        'url': 'https://thumb.test/thumb1',
      });
    });

    test(
      'createAndParse writes source and deletes it on parse failure',
      () async {
        final parser = ComicSourceParser();

        final source = await parser.createAndParse(
          _sourceScript(
            key: 'created_source',
            body: '''
            comic = {
              loadInfo: () => ({
                title: 'Created',
                cover: 'cover',
                tags: {},
              }),
              loadEp: () => ({ images: [] }),
            }
          ''',
          ),
          'created_source',
        );

        expect(await File(source.filePath).exists(), isTrue);
        expect(source.filePath, endsWith('created_source.js'));

        await expectLater(
          parser.createAndParse('const broken = true', 'broken_source'),
          throwsA(isA<ComicSourceParseException>()),
        );

        final brokenFile = File(
          '${tempDir.path}${Platform.pathSeparator}comic_source'
          '${Platform.pathSeparator}broken_source.js',
        );
        expect(await brokenFile.exists(), isFalse);
      },
    );
  });

  group('ComicSource', () {
    test('persists and reloads per-source data', () async {
      final source = await ComicSourceParser().parse(
        _sourceScript(
          key: 'data_source',
          body: '''
            comic = {
              loadInfo: () => ({
                title: 'Data',
                cover: 'cover',
                tags: {},
              }),
              loadEp: () => ({ images: [] }),
            }
          ''',
        ),
        'data_source.js',
      );

      var changed = false;
      await ComicSourceManager().init(
        dataPath: tempDir.path,
        dataChangedHandler: () => changed = true,
      );

      source.data = {
        'account': ['user', 'password'],
        'nested': {'value': 1},
      };
      await source.saveData();

      expect(changed, isTrue);

      final reloaded = await ComicSourceParser().parse(
        _sourceScript(
          key: 'data_source_reloaded',
          body: '''
            comic = {
              loadInfo: () => ({
                title: 'Reloaded',
                cover: 'cover',
                tags: {},
              }),
              loadEp: () => ({ images: [] }),
            }
          ''',
        ),
        'data_source_reloaded.js',
      );

      final dataFile = File(
        '${tempDir.path}${Platform.pathSeparator}comic_source'
        '${Platform.pathSeparator}data_source_reloaded.data',
      );
      await dataFile.writeAsString('{"nested":{"value":2},"flag":true}');
      await reloaded.loadData();

      expect(reloaded.data, {
        'nested': {'value': 2},
        'flag': true,
      });
    });
  });
}

String _sourceScript({
  required String key,
  String name = 'Test Source',
  String version = '1.0.0',
  String url = '',
  String? minAppVersion = '0.0.0',
  required String body,
}) {
  final minVersionLine = minAppVersion == null
      ? ''
      : "minAppVersion = '$minAppVersion'";
  return '''
class ${_classNameForKey(key)} extends ComicSource {
  name = '$name'
  key = '$key'
  version = '$version'
  url = '$url'
  $minVersionLine
  search = {}

$body
}
''';
}

String _classNameForKey(String key) {
  final sanitized = key.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
  return 'Source${sanitized.hashCode.abs()}';
}
