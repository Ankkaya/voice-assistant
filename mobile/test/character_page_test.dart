import 'package:child_voice_call/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows both configured characters', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: VoiceCallApp()));
    await tester.pumpAndSettle();

    expect(find.text('拉布拉多队长'), findsOneWidget);
    expect(find.text('莱德'), findsOneWidget);
  });
}
