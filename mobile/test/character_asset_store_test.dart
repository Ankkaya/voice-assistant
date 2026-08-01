import 'dart:io';

import 'package:child_voice_call/services/character_asset_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory temporaryDirectory;
  late Directory root;
  late FileCharacterAssetStore store;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'character-assets-test-',
    );
    root = Directory('${temporaryDirectory.path}/support');
    store = FileCharacterAssetStore(root: root);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('avatar import writes a square at most 1024px and 2 MB', () async {
    final source = File('${temporaryDirectory.path}/wide.jpg');
    final sourceImage = img.Image(width: 1600, height: 900);
    await source.writeAsBytes(img.encodeJpg(sourceImage, quality: 95));

    final relative = await store.importAvatar(
      source.path,
      'custom_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    final output = File('${root.path}/$relative');
    final decoded = img.decodeImage(await output.readAsBytes())!;
    expect(decoded.width, decoded.height);
    expect(decoded.width, lessThanOrEqualTo(1024));
    expect(await output.length(), lessThanOrEqualTo(maxAvatarBytes));
  });

  test('voice import rejects fake wav and files over ten megabytes', () async {
    final fakeWav = File('${temporaryDirectory.path}/fake.wav');
    await fakeWav.writeAsBytes('not really a wave'.codeUnits);
    final oversizedMp3 = File('${temporaryDirectory.path}/large.mp3');
    await oversizedMp3.writeAsBytes(
      List<int>.filled(maxVoiceReferenceBytes + 1, 0),
    );

    await expectLater(
      store.importVoiceReference(fakeWav.path, 'custom_id'),
      throwsFormatException,
    );
    await expectLater(
      store.importVoiceReference(oversizedMp3.path, 'custom_id'),
      throwsRangeError,
    );
  });

  test('voice import accepts matching WAV signature and keeps bytes', () async {
    final wav = File('${temporaryDirectory.path}/voice.wav');
    final bytes = <int>[
      ...'RIFF'.codeUnits,
      4,
      0,
      0,
      0,
      ...'WAVE'.codeUnits,
      ...'authorized'.codeUnits,
    ];
    await wav.writeAsBytes(bytes);

    final relative = await store.importVoiceReference(wav.path, 'custom_id');

    expect(relative, startsWith('voices/custom_id_'));
    expect(await File('${root.path}/$relative').readAsBytes(), bytes);
  });

  test('purge removes only unreferenced private assets', () async {
    final avatars = Directory('${root.path}/avatars');
    await avatars.create(recursive: true);
    final kept = File('${avatars.path}/kept.jpg');
    final orphan = File('${avatars.path}/orphan.jpg');
    await kept.writeAsBytes([1]);
    await orphan.writeAsBytes([2]);

    await store.purgeOrphans({'avatars/kept.jpg'});

    expect(await kept.exists(), isTrue);
    expect(await orphan.exists(), isFalse);
  });

  test('delete rejects traversal outside private asset folders', () async {
    expect(
      () => store.deleteRelative('../custom_characters.json'),
      throwsFormatException,
    );
  });
}
