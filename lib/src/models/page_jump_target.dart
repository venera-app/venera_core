class PageJumpTarget {
  final String sourceKey;

  final String page;

  final Map<String, dynamic>? attributes;

  const PageJumpTarget(this.sourceKey, this.page, this.attributes);

  static PageJumpTarget parse(String sourceKey, dynamic value) {
    if (value is Map) {
      if (value['page'] != null) {
        return PageJumpTarget(
          sourceKey,
          value["page"] ?? "search",
          value["attributes"],
        );
      } else if (value["action"] != null) {
        // old version `onClickTag`
        var page = value["action"];
        if (page == "search") {
          return PageJumpTarget(sourceKey, "search", {
            "text": value["keyword"],
          });
        } else if (page == "category") {
          return PageJumpTarget(sourceKey, "category", {
            "category": value["keyword"],
            "param": value["param"],
          });
        } else {
          return PageJumpTarget(sourceKey, page, null);
        }
      }
    } else if (value is String) {
      // old version string encoding. search: `search:keyword`, category: `category:keyword` or `category:keyword@param`
      var segments = value.split(":");
      var page = segments[0];
      if (page == "search") {
        return PageJumpTarget(sourceKey, "search", {"text": segments[1]});
      } else if (page == "category") {
        var c = segments[1];
        if (c.contains('@')) {
          var parts = c.split('@');
          return PageJumpTarget(sourceKey, "category", {
            "category": parts[0],
            "param": parts[1],
          });
        } else {
          return PageJumpTarget(sourceKey, "category", {"category": c});
        }
      } else {
        return PageJumpTarget(sourceKey, page, null);
      }
    }
    return PageJumpTarget(sourceKey, "Invalid Data", null);
  }

  @Deprecated('Page navigation belongs to the application layer.')
  void jump(Object context) {
    throw UnsupportedError(
      'PageJumpTarget.jump is not available in venera_core',
    );
  }
}
