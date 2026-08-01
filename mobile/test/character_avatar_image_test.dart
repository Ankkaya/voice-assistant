import 'dart:io';

import 'package:child_voice_call/models/custom_character.dart';
import 'package:child_voice_call/widgets/character_avatar_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Widget testApp(CharacterAvatarImage image) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 100, height: 100, child: image)),
);

void main() {
  testWidgets('renders local avatar and falls back when it is missing', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('avatar-widget-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final existing = File('${directory.path}/avatar.png');
    existing.writeAsBytesSync(img.encodePng(img.Image(width: 2, height: 2)));

    await tester.pumpWidget(
      testApp(
        CharacterAvatarImage(
          avatar: CharacterAvatarRef.localFile(existing.path),
          fallbackColor: Colors.blue,
        ),
      ),
    );
    expect(find.byType(Image), findsOneWidget);

    await tester.pumpWidget(
      testApp(
        const CharacterAvatarImage(
          avatar: CharacterAvatarRef.localFile('/missing/avatar.jpg'),
          fallbackColor: Colors.blue,
        ),
      ),
    );
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
  });

  testWidgets('maps bundled avatar IDs to application icons', (tester) async {
    await tester.pumpWidget(
      testApp(
        const CharacterAvatarImage(
          avatar: CharacterAvatarRef.bundled('rocket'),
          fallbackColor: Colors.purple,
        ),
      ),
    );

    expect(find.byIcon(Icons.rocket_launch_rounded), findsOneWidget);
  });
}
