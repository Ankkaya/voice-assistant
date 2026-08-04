import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const _repositoryOwner = 'Ankkaya';
const _repositoryName = 'voice-assistant';
const _maximumResponseBytes = 256 * 1024;

final _latestReleaseEndpoint = Uri.https(
  'api.github.com',
  '/repos/$_repositoryOwner/$_repositoryName/releases/latest',
);

final _releaseTagPattern = RegExp(
  r'^v([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?)$',
);

class AppVersion {
  const AppVersion({required this.versionName, required this.versionCode});

  factory AppVersion.parse({
    required String versionName,
    required String buildNumber,
  }) {
    final normalizedName = versionName.trim();
    final versionCode = int.tryParse(buildNumber.trim());
    if (_SemanticVersion.tryParse(normalizedName) == null ||
        versionCode == null ||
        versionCode < 1) {
      throw const AppUpdateException(AppUpdateFailure.invalidResponse);
    }
    return AppVersion(versionName: normalizedName, versionCode: versionCode);
  }

  final String versionName;
  final int versionCode;

  String get displayName => '$versionName ($versionCode)';
}

class GitHubRelease {
  const GitHubRelease({
    required this.tagName,
    required this.versionName,
    required this.publishedAt,
    required this.releaseNotes,
    required this.apkSizeBytes,
    required this.apkDownloadUrl,
    required this.releasePageUrl,
    this.apkDigest,
  });

  final String tagName;
  final String versionName;
  final DateTime publishedAt;
  final String releaseNotes;
  final int apkSizeBytes;
  final Uri apkDownloadUrl;
  final Uri releasePageUrl;
  final String? apkDigest;
}

class AppUpdateResult {
  const AppUpdateResult({required this.currentVersion, required this.release});

  final AppVersion currentVersion;
  final GitHubRelease release;

  bool get updateAvailable =>
      _SemanticVersion.parse(
        release.versionName,
      ).compareTo(_SemanticVersion.parse(currentVersion.versionName)) >
      0;
}

enum AppUpdateFailure { network, rateLimited, notFound, invalidResponse }

class AppUpdateException implements Exception {
  const AppUpdateException(this.failure);

  final AppUpdateFailure failure;
}

abstract interface class AppUpdateService {
  Future<AppVersion> currentVersion();

  Future<AppUpdateResult> check();

  Future<bool> openDownload(GitHubRelease release);

  void close();
}

class GitHubAppUpdateService implements AppUpdateService {
  GitHubAppUpdateService({
    http.Client? client,
    Future<AppVersion> Function()? versionLoader,
    Future<bool> Function(Uri url)? urlLauncher,
    Uri? endpoint,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _versionLoader = versionLoader ?? _loadPlatformVersion,
       _urlLauncher = urlLauncher ?? _launchExternalUrl,
       _endpoint = endpoint ?? _latestReleaseEndpoint;

  final http.Client _client;
  final bool _ownsClient;
  final Future<AppVersion> Function() _versionLoader;
  final Future<bool> Function(Uri url) _urlLauncher;
  final Uri _endpoint;

  AppVersion? _currentVersion;
  Future<AppVersion>? _versionInFlight;
  Future<AppUpdateResult>? _checkInFlight;

  static Future<AppVersion> _loadPlatformVersion() async {
    final info = await PackageInfo.fromPlatform();
    return AppVersion.parse(
      versionName: info.version,
      buildNumber: info.buildNumber,
    );
  }

  static Future<bool> _launchExternalUrl(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  @override
  Future<AppVersion> currentVersion() {
    final cached = _currentVersion;
    if (cached != null) return Future.value(cached);
    final existing = _versionInFlight;
    if (existing != null) return existing;

    late final Future<AppVersion> request;
    request = _versionLoader()
        .then((version) {
          _currentVersion = version;
          return version;
        })
        .whenComplete(() {
          if (identical(_versionInFlight, request)) {
            _versionInFlight = null;
          }
        });
    _versionInFlight = request;
    return request;
  }

  @override
  Future<AppUpdateResult> check() {
    final existing = _checkInFlight;
    if (existing != null) return existing;

    late final Future<AppUpdateResult> request;
    request = _check().whenComplete(() {
      if (identical(_checkInFlight, request)) {
        _checkInFlight = null;
      }
    });
    _checkInFlight = request;
    return request;
  }

  Future<AppUpdateResult> _check() async {
    try {
      final version = await currentVersion();
      final response = await _client
          .get(
            _endpoint,
            headers: const {
              'accept': 'application/vnd.github+json',
              'user-agent': 'voice-assistant-android',
              'x-github-api-version': '2026-03-10',
            },
          )
          .timeout(const Duration(seconds: 5));

      switch (response.statusCode) {
        case 200:
          break;
        case 403:
        case 429:
          throw const AppUpdateException(AppUpdateFailure.rateLimited);
        case 404:
          throw const AppUpdateException(AppUpdateFailure.notFound);
        default:
          if (response.statusCode >= 500) {
            throw const AppUpdateException(AppUpdateFailure.network);
          }
          throw const AppUpdateException(AppUpdateFailure.invalidResponse);
      }

      if (response.bodyBytes.length > _maximumResponseBytes) {
        throw const AppUpdateException(AppUpdateFailure.invalidResponse);
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const AppUpdateException(AppUpdateFailure.invalidResponse);
      }
      return AppUpdateResult(
        currentVersion: version,
        release: _parseRelease(decoded),
      );
    } on AppUpdateException {
      rethrow;
    } on TimeoutException {
      throw const AppUpdateException(AppUpdateFailure.network);
    } on http.ClientException {
      throw const AppUpdateException(AppUpdateFailure.network);
    } on FormatException {
      throw const AppUpdateException(AppUpdateFailure.invalidResponse);
    } on Object {
      throw const AppUpdateException(AppUpdateFailure.invalidResponse);
    }
  }

  @override
  Future<bool> openDownload(GitHubRelease release) async {
    if (!_isTrustedDownloadUrl(
      release.apkDownloadUrl,
      release.tagName,
      _expectedApkName(release.tagName),
    )) {
      return false;
    }
    try {
      return await _urlLauncher(release.apkDownloadUrl);
    } on Object {
      return false;
    }
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}

GitHubRelease _parseRelease(Map<String, dynamic> payload) {
  if (payload['draft'] != false || payload['prerelease'] != false) {
    throw const AppUpdateException(AppUpdateFailure.invalidResponse);
  }

  final tagName = payload['tag_name'];
  final pageUrlValue = payload['html_url'];
  final publishedAtValue = payload['published_at'];
  final assets = payload['assets'];
  if (tagName is! String ||
      pageUrlValue is! String ||
      publishedAtValue is! String ||
      assets is! List) {
    throw const AppUpdateException(AppUpdateFailure.invalidResponse);
  }

  final tagMatch = _releaseTagPattern.firstMatch(tagName);
  if (tagMatch == null) {
    throw const AppUpdateException(AppUpdateFailure.invalidResponse);
  }
  final versionName = tagMatch.group(1)!;
  if (_SemanticVersion.tryParse(versionName) == null) {
    throw const AppUpdateException(AppUpdateFailure.invalidResponse);
  }
  final publishedAt = DateTime.tryParse(publishedAtValue);
  final pageUrl = Uri.tryParse(pageUrlValue);
  if (publishedAt == null ||
      pageUrl == null ||
      !_isTrustedReleasePageUrl(pageUrl, tagName)) {
    throw const AppUpdateException(AppUpdateFailure.invalidResponse);
  }

  final expectedApkName = _expectedApkName(tagName);
  final matchingAssets = <Map<String, dynamic>>[];
  for (final asset in assets) {
    if (asset is Map<String, dynamic> && asset['name'] == expectedApkName) {
      matchingAssets.add(asset);
    }
  }
  if (matchingAssets.length != 1) {
    throw const AppUpdateException(AppUpdateFailure.invalidResponse);
  }

  final apk = matchingAssets.single;
  final size = apk['size'];
  final downloadUrlValue = apk['browser_download_url'];
  if (apk['state'] != 'uploaded' ||
      size is! int ||
      size < 1 ||
      downloadUrlValue is! String) {
    throw const AppUpdateException(AppUpdateFailure.invalidResponse);
  }
  final downloadUrl = Uri.tryParse(downloadUrlValue);
  if (downloadUrl == null ||
      !_isTrustedDownloadUrl(downloadUrl, tagName, expectedApkName)) {
    throw const AppUpdateException(AppUpdateFailure.invalidResponse);
  }

  final digestValue = apk['digest'];
  String? digest;
  if (digestValue != null) {
    if (digestValue is! String ||
        !RegExp(r'^sha256:[0-9a-fA-F]{64}$').hasMatch(digestValue)) {
      throw const AppUpdateException(AppUpdateFailure.invalidResponse);
    }
    digest = digestValue.toLowerCase();
  }

  return GitHubRelease(
    tagName: tagName,
    versionName: versionName,
    publishedAt: publishedAt,
    releaseNotes: _releaseNotesSummary(payload['body']),
    apkSizeBytes: size,
    apkDownloadUrl: downloadUrl,
    releasePageUrl: pageUrl,
    apkDigest: digest,
  );
}

String _expectedApkName(String tagName) => 'child-voice-$tagName.apk';

bool _isTrustedReleasePageUrl(Uri uri, String tagName) =>
    _isBaseGitHubUrl(uri) &&
    _pathEquals(uri, [
      _repositoryOwner,
      _repositoryName,
      'releases',
      'tag',
      tagName,
    ]);

bool _isTrustedDownloadUrl(Uri uri, String tagName, String apkName) =>
    _isBaseGitHubUrl(uri) &&
    _pathEquals(uri, [
      _repositoryOwner,
      _repositoryName,
      'releases',
      'download',
      tagName,
      apkName,
    ]);

bool _isBaseGitHubUrl(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host == 'github.com' &&
    !uri.hasPort &&
    uri.userInfo.isEmpty &&
    uri.query.isEmpty &&
    uri.fragment.isEmpty;

bool _pathEquals(Uri uri, List<String> expected) {
  try {
    final segments = uri.pathSegments;
    if (segments.length != expected.length) return false;
    for (var index = 0; index < expected.length; index++) {
      if (segments[index] != expected[index]) return false;
    }
    return true;
  } on FormatException {
    return false;
  }
}

String _releaseNotesSummary(Object? body) {
  if (body is! String || body.trim().isEmpty) return '';
  final lines = body
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .take(10)
      .toList(growable: false);
  final summary = lines.join('\n');
  if (summary.length <= 1500) return summary;
  return '${summary.substring(0, 1499)}…';
}

class _SemanticVersion implements Comparable<_SemanticVersion> {
  const _SemanticVersion(this.major, this.minor, this.patch, this.prerelease);

  final int major;
  final int minor;
  final int patch;
  final List<String> prerelease;

  static final _pattern = RegExp(
    r'^([0-9]+)\.([0-9]+)\.([0-9]+)(?:-([0-9A-Za-z.-]+))?$',
  );

  static _SemanticVersion parse(String value) {
    final parsed = tryParse(value);
    if (parsed == null) throw const FormatException('Invalid app version');
    return parsed;
  }

  static _SemanticVersion? tryParse(String value) {
    final match = _pattern.firstMatch(value.trim());
    if (match == null) return null;
    final major = int.tryParse(match.group(1)!);
    final minor = int.tryParse(match.group(2)!);
    final patch = int.tryParse(match.group(3)!);
    if (major == null || minor == null || patch == null) return null;
    final prereleaseValue = match.group(4);
    final prerelease = prereleaseValue == null
        ? const <String>[]
        : prereleaseValue.split('.');
    if (prerelease.any((identifier) => identifier.isEmpty)) return null;
    return _SemanticVersion(major, minor, patch, prerelease);
  }

  @override
  int compareTo(_SemanticVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final comparison = pair.$1.compareTo(pair.$2);
      if (comparison != 0) return comparison;
    }
    if (prerelease.isEmpty && other.prerelease.isEmpty) return 0;
    if (prerelease.isEmpty) return 1;
    if (other.prerelease.isEmpty) return -1;

    final sharedLength = prerelease.length < other.prerelease.length
        ? prerelease.length
        : other.prerelease.length;
    for (var index = 0; index < sharedLength; index++) {
      final left = prerelease[index];
      final right = other.prerelease[index];
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      int comparison;
      if (leftNumber != null && rightNumber != null) {
        comparison = leftNumber.compareTo(rightNumber);
      } else if (leftNumber != null) {
        comparison = -1;
      } else if (rightNumber != null) {
        comparison = 1;
      } else {
        comparison = left.compareTo(right);
      }
      if (comparison != 0) return comparison;
    }
    return prerelease.length.compareTo(other.prerelease.length);
  }
}
