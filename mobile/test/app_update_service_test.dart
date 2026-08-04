import 'dart:convert';

import 'package:child_voice_call/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const currentVersion = AppVersion(versionName: '0.1.0', versionCode: 1);

Map<String, Object?> releasePayload({
  String tag = 'v0.2.0',
  String? htmlUrl,
  String? downloadUrl,
  String assetState = 'uploaded',
  int assetSize = 50 * 1024 * 1024,
  bool draft = false,
  bool prerelease = false,
  Object? assets,
  String body = '- 增加版本更新\n- 修复通话问题',
}) {
  final assetName = 'child-voice-$tag.apk';
  return {
    'tag_name': tag,
    'html_url':
        htmlUrl ??
        'https://github.com/Ankkaya/voice-assistant/releases/tag/$tag',
    'body': body,
    'published_at': '2026-08-04T08:00:00Z',
    'draft': draft,
    'prerelease': prerelease,
    'assets':
        assets ??
        [
          {
            'name': assetName,
            'state': assetState,
            'size': assetSize,
            'browser_download_url':
                downloadUrl ??
                'https://github.com/Ankkaya/voice-assistant/'
                    'releases/download/$tag/$assetName',
            'digest':
                'sha256:'
                '0123456789abcdef0123456789abcdef'
                '0123456789abcdef0123456789abcdef',
          },
        ],
  };
}

GitHubAppUpdateService serviceFor(
  Future<http.Response> Function(http.Request request) handler, {
  Future<bool> Function(Uri url)? launcher,
  AppVersion version = currentVersion,
}) => GitHubAppUpdateService(
  client: MockClient(handler),
  versionLoader: () async => version,
  urlLauncher: launcher,
);

http.Response jsonResponse(Object? body, {int statusCode = 200}) =>
    http.Response(
      jsonEncode(body),
      statusCode,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('parses the latest release and sends GitHub API headers', () async {
    late http.Request captured;
    final service = serviceFor((request) async {
      captured = request;
      return jsonResponse(releasePayload());
    });
    addTearDown(service.close);

    final result = await service.check();

    expect(result.updateAvailable, isTrue);
    expect(result.currentVersion.displayName, '0.1.0 (1)');
    expect(result.release.versionName, '0.2.0');
    expect(result.release.apkSizeBytes, 50 * 1024 * 1024);
    expect(result.release.releaseNotes, contains('增加版本更新'));
    expect(
      captured.url.toString(),
      'https://api.github.com/repos/Ankkaya/voice-assistant/releases/latest',
    );
    expect(captured.headers['accept'], 'application/vnd.github+json');
    expect(captured.headers['user-agent'], 'voice-assistant-android');
    expect(captured.headers['x-github-api-version'], '2026-03-10');
  });

  test('uses semantic versions rather than Android build numbers', () async {
    final service = serviceFor(
      (_) async => jsonResponse(releasePayload(tag: 'v1.9.9')),
      version: const AppVersion(versionName: '2.0.0', versionCode: 1),
    );
    addTearDown(service.close);

    final result = await service.check();

    expect(result.updateAvailable, isFalse);
  });

  test('coalesces concurrent checks into one GitHub request', () async {
    var requestCount = 0;
    final service = serviceFor((_) async {
      requestCount += 1;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return jsonResponse(releasePayload());
    });
    addTearDown(service.close);

    final results = await Future.wait([service.check(), service.check()]);

    expect(requestCount, 1);
    expect(results, hasLength(2));
    expect(results.first.updateAvailable, isTrue);
  });

  test('opens only the validated APK download URL', () async {
    Uri? launchedUrl;
    final service = serviceFor(
      (_) async => jsonResponse(releasePayload()),
      launcher: (url) async {
        launchedUrl = url;
        return true;
      },
    );
    addTearDown(service.close);
    final result = await service.check();

    expect(await service.openDownload(result.release), isTrue);
    expect(launchedUrl, result.release.apkDownloadUrl);

    final untrusted = GitHubRelease(
      tagName: result.release.tagName,
      versionName: result.release.versionName,
      publishedAt: result.release.publishedAt,
      releaseNotes: result.release.releaseNotes,
      apkSizeBytes: result.release.apkSizeBytes,
      apkDownloadUrl: Uri.parse('https://example.com/update.apk'),
      releasePageUrl: result.release.releasePageUrl,
    );
    launchedUrl = null;
    expect(await service.openDownload(untrusted), isFalse);
    expect(launchedUrl, isNull);
  });

  test('maps GitHub response statuses to typed failures', () async {
    for (final testCase in [
      (403, AppUpdateFailure.rateLimited),
      (429, AppUpdateFailure.rateLimited),
      (404, AppUpdateFailure.notFound),
      (500, AppUpdateFailure.network),
      (400, AppUpdateFailure.invalidResponse),
    ]) {
      final service = serviceFor((_) async => http.Response('', testCase.$1));
      addTearDown(service.close);

      await expectLater(
        service.check(),
        throwsA(
          isA<AppUpdateException>().having(
            (error) => error.failure,
            'failure',
            testCase.$2,
          ),
        ),
      );
    }
  });

  test('rejects unsafe or incomplete releases', () async {
    final invalidPayloads = [
      releasePayload(tag: 'v0.2.0+2'),
      releasePayload(tag: '0.2.0'),
      releasePayload(prerelease: true),
      releasePayload(assets: <Object>[]),
      releasePayload(assetState: 'new'),
      releasePayload(assetSize: 0),
      releasePayload(
        htmlUrl:
            'https://example.com/Ankkaya/voice-assistant/releases/tag/v0.2.0',
      ),
      releasePayload(downloadUrl: 'https://example.com/update.apk'),
    ];

    for (final payload in invalidPayloads) {
      final service = serviceFor((_) async => jsonResponse(payload));
      addTearDown(service.close);

      await expectLater(
        service.check(),
        throwsA(
          isA<AppUpdateException>().having(
            (error) => error.failure,
            'failure',
            AppUpdateFailure.invalidResponse,
          ),
        ),
      );
    }
  });

  test('rejects invalid local build numbers', () {
    expect(
      () => AppVersion.parse(versionName: '0.1.0', buildNumber: 'dev'),
      throwsA(isA<AppUpdateException>()),
    );
    expect(
      () => AppVersion.parse(versionName: '0.1.0', buildNumber: '0'),
      throwsA(isA<AppUpdateException>()),
    );
  });

  test('limits release notes to ten lines and 1500 characters', () async {
    final longLine = List.filled(200, 'x').join();
    final body = List.generate(12, (index) => '$longLine-$index').join('\n');
    final service = serviceFor(
      (_) async => jsonResponse(releasePayload(body: body)),
    );
    addTearDown(service.close);

    final result = await service.check();

    expect(result.release.releaseNotes.length, 1500);
    expect(result.release.releaseNotes.endsWith('…'), isTrue);
    expect(result.release.releaseNotes, isNot(contains('-10')));
  });
}
