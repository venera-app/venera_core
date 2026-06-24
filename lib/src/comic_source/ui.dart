part of 'comic_source.dart';

abstract interface class ComicSourceUiHandler {
  FutureOr<void> showMessage(String message);

  FutureOr<void> showDialog({
    String? title,
    String? content,
    required List<ComicSourceDialogAction> actions,
  });

  FutureOr<void> launchUrl(String url);

  int showLoading({JSAutoFreeFunction? onCancel});

  FutureOr<void> cancelLoading(int id);

  FutureOr<String?> showInputDialog({
    required String title,
    JSAutoFreeFunction? validator,
    dynamic image,
  });

  FutureOr<int?> showSelectDialog({
    required String title,
    required List<String> options,
    int? initialIndex,
  });

  FutureOr<void> setClipboard(String text);

  FutureOr<String?> getClipboard();
}

class ComicSourceDialogAction {
  final String text;
  final String style;
  final JSAutoFreeFunction callback;

  const ComicSourceDialogAction({
    required this.text,
    required this.style,
    required this.callback,
  });
}
