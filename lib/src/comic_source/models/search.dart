part of '../comic_source.dart';

typedef SearchFunction =
    Future<Res<List<Comic>>> Function(
      String keyword,
      int page,
      List<String> searchOption,
    );

typedef SearchNextFunction =
    Future<Res<List<Comic>>> Function(
      String keyword,
      String? next,
      List<String> searchOption,
    );

class SearchPageData {
  /// If this is not null, the default value of search options will be first element.
  final List<SearchOptions>? searchOptions;

  final SearchFunction? loadPage;

  final SearchNextFunction? loadNext;

  const SearchPageData(this.searchOptions, this.loadPage, this.loadNext);
}

class SearchOptions {
  final LinkedHashMap<String, String> options;

  final String label;

  final String type;

  final String? defaultVal;

  const SearchOptions(this.options, this.label, this.type, this.defaultVal);

  String get defaultValue => defaultVal ?? options.keys.firstOrNull ?? "";
}
