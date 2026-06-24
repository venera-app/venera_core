part of '../comic_source.dart';

class AccountConfig {
  final LoginFunction? login;

  final String? loginWebsite;

  final String? registerWebsite;

  final void Function() logout;

  final List<AccountInfoItem> infoItems;

  final bool Function(String url, String title)? checkLoginStatus;

  final void Function()? onLoginWithWebviewSuccess;

  final List<String>? cookieFields;

  final Future<bool> Function(List<String>)? validateCookies;

  const AccountConfig(
    this.login,
    this.loginWebsite,
    this.registerWebsite,
    this.logout,
    this.checkLoginStatus,
    this.onLoginWithWebviewSuccess,
    this.cookieFields,
    this.validateCookies,
  ) : infoItems = const [];
}

class AccountInfoItem {
  final String title;
  final String Function()? data;
  final void Function()? onTap;
  final Object? builder;

  AccountInfoItem({required this.title, this.data, this.onTap, this.builder});
}

class LoadImageRequest {
  String url;

  Map<String, String> headers;

  LoadImageRequest(this.url, this.headers);
}
