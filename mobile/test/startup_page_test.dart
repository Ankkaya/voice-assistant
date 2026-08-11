import 'package:child_voice_call/pages/startup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('startup page fills the screen with the supplied image', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: StartupPage()));

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, const AssetImage(StartupPage.assetPath));
    expect(image.fit, BoxFit.cover);
    expect(image.alignment, Alignment.topCenter);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
