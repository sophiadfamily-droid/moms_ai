import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moms_ai/screens/welcome_screen.dart';
import 'package:moms_ai/theme/app_theme.dart';

void main() {
  const fontAssets = <String>[
    'assets/fonts/playfair_display/PlayfairDisplay[wght].ttf',
    'assets/fonts/cormorant_garamond/CormorantGaramond[wght].ttf',
    'assets/fonts/nunito/Nunito[wght].ttf',
  ];

  test('Local font assets are declared, present, and non-empty', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    for (final asset in fontAssets) {
      expect(pubspec, contains('- asset: $asset'));
      expect(File(asset).lengthSync(), greaterThan(0));
    }
  });

  test('Application source does not use runtime Google Fonts loading', () {
    final dartSources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final source in dartSources) {
      final contents = source.readAsStringSync();
      expect(contents, isNot(contains('GoogleFonts')), reason: source.path);
      expect(contents, isNot(contains('google_fonts')), reason: source.path);
      expect(contents, isNot(contains('fonts.gstatic.com')),
          reason: source.path);
    }
  });

  testWidgets('Theme and first screen build without network font loading', (
    WidgetTester tester,
  ) async {
    var httpClientCreations = 0;

    await HttpOverrides.runZoned(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: WelcomeScreen(onStart: () {}),
          ),
        );
        await tester.pump();
      },
      createHttpClient: (context) {
        httpClientCreations++;
        throw StateError('The first screen attempted to access the network.');
      },
    );

    expect(tester.takeException(), isNull);
    expect(httpClientCreations, 0);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(
      AppTheme.lightTheme.textTheme.headlineLarge?.fontFamily,
      AppTheme.displayFontFamily,
    );
    expect(
      AppTheme.lightTheme.textTheme.bodyLarge?.fontFamily,
      AppTheme.bodyFontFamily,
    );
    expect(AppTheme.displayFontFamily, 'PlayfairDisplay');
    expect(
      AppTheme.secondaryDisplayFontFamily,
      'CormorantGaramond',
    );
    expect(AppTheme.bodyFontFamily, 'Nunito');
  });

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
