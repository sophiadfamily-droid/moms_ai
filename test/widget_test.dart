import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moms_ai/screens/welcome_screen.dart';

void main() {
  testWidgets('Welcome screen displays the splash image', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WelcomeScreen(onStart: () {}),
      ),
    );

    expect(find.byType(Image), findsOneWidget);

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
    expect((image.image as AssetImage).assetName, 'assets/images/splash.png');
  });

  testWidgets('Welcome screen calls onStart after its delay', (
    WidgetTester tester,
  ) async {
    var started = false;

    await tester.pumpWidget(
      MaterialApp(
        home: WelcomeScreen(
          onStart: () {
            started = true;
          },
        ),
      ),
    );

    expect(started, isFalse);

    await tester.pump(const Duration(milliseconds: 1800));

    expect(started, isTrue);
  });

  testWidgets('Welcome screen can be skipped by tapping', (
    WidgetTester tester,
  ) async {
    var started = false;

    await tester.pumpWidget(
      MaterialApp(
        home: WelcomeScreen(
          onStart: () {
            started = true;
          },
        ),
      ),
    );

    await tester.tap(find.byType(GestureDetector));
    await tester.pump();

    expect(started, isTrue);
  });
}
