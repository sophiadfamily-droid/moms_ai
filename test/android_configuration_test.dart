import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const packageName = 'com.sophiadfamily.zeliaaiapp';
  const firebaseAppId = '1:664245687438:android:176b756db5b132c6ca65df';

  test('Android production identity and Firebase configuration stay aligned',
      () {
    final repositoryRoot = _findRepositoryRoot();

    String readRepositoryFile(String path) =>
        File('${repositoryRoot.path}/$path').readAsStringSync();

    String singleActiveValue(RegExp pattern, String contents) {
      final matches = pattern.allMatches(contents).toList();
      expect(matches, hasLength(1));
      return matches.single.group(1)!;
    }

    final gradle = readRepositoryFile('android/app/build.gradle.kts');
    final activeGradle = _withoutMultilineComments(gradle);
    final namespace = singleActiveValue(
      RegExp(r'^\s*namespace\s*=\s*"([^"]+)"\s*$', multiLine: true),
      activeGradle,
    );
    final applicationId = singleActiveValue(
      RegExp(r'^\s*applicationId\s*=\s*"([^"]+)"\s*$', multiLine: true),
      activeGradle,
    );
    expect(namespace, packageName);
    expect(applicationId, packageName);
    expect(namespace, isNot('com.example.moms_ai'));
    expect(applicationId, isNot('com.example.moms_ai'));

    final mainActivity = File(
      '${repositoryRoot.path}/android/app/src/main/kotlin/com/sophiadfamily/'
      'zeliaaiapp/MainActivity.kt',
    );
    expect(mainActivity.existsSync(), isTrue);
    final activeMainActivity = _withoutMultilineComments(
      mainActivity.readAsStringSync(),
    );
    final kotlinPackage = singleActiveValue(
      RegExp(r'^\s*package\s+([A-Za-z_][\w.]*)\s*$', multiLine: true),
      activeMainActivity,
    );
    expect(kotlinPackage, packageName);
    expect(kotlinPackage, isNot('com.example.moms_ai'));
    expect(
      File(
        '${repositoryRoot.path}/android/app/src/main/kotlin/'
        'com/example/moms_ai/MainActivity.kt',
      ).existsSync(),
      isFalse,
    );

    final googleServices = jsonDecode(
      readRepositoryFile('android/app/google-services.json'),
    ) as Map<String, dynamic>;
    final clients = googleServices['client'] as List<dynamic>;
    final productionClients = clients.whereType<Map<String, dynamic>>().where(
      (client) {
        final clientInfo = client['client_info'] as Map<String, dynamic>;
        final androidInfo =
            clientInfo['android_client_info'] as Map<String, dynamic>;
        return androidInfo['package_name'] == packageName;
      },
    ).toList();
    expect(productionClients, hasLength(1));
    final productionClientInfo =
        productionClients.single['client_info'] as Map<String, dynamic>;
    expect(productionClientInfo['mobilesdk_app_id'], firebaseAppId);

    final firebaseOptions = readRepositoryFile('lib/firebase_options.dart');
    final androidOptionsBlock = singleActiveValue(
      RegExp(
        r'^\s*static const FirebaseOptions android = FirebaseOptions\('
        r'(.*?)^\s*\);',
        multiLine: true,
        dotAll: true,
      ),
      firebaseOptions,
    );
    final configuredAndroidAppId = singleActiveValue(
      RegExp(r"^\s*appId:\s*'([^']+)',\s*$", multiLine: true),
      androidOptionsBlock,
    );
    expect(configuredAndroidAppId, firebaseAppId);

    final firebaseJson =
        jsonDecode(readRepositoryFile('firebase.json')) as Map<String, dynamic>;
    final flutterConfig = firebaseJson['flutter'] as Map<String, dynamic>;
    final platforms = flutterConfig['platforms'] as Map<String, dynamic>;
    final androidConfig = platforms['android'] as Map<String, dynamic>;
    final buildConfigurations =
        androidConfig['buildConfigurations'] as Map<String, dynamic>;
    expect(buildConfigurations, hasLength(1));
    final activeAndroidConfig =
        buildConfigurations.values.single as Map<String, dynamic>;
    expect(activeAndroidConfig['projectId'], 'zelia-ai-app');
    expect(activeAndroidConfig['appId'], firebaseAppId);
  });

  test('Android Release signing is dedicated and fails closed', () {
    final repositoryRoot = _findRepositoryRoot();
    final gradle = _withoutMultilineComments(
      File('${repositoryRoot.path}/android/app/build.gradle.kts')
          .readAsStringSync(),
    );

    expect(
      RegExp(
        r'^\s*signingConfig\s*=\s*signingConfigs\.getByName\("release"\)\s*$',
        multiLine: true,
      ).allMatches(gradle),
      hasLength(1),
    );
    expect(
      RegExp(
        r'^\s*signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)\s*$',
        multiLine: true,
      ).hasMatch(gradle),
      isFalse,
    );
    expect(
      RegExp(r'^\s*create\("release"\)\s*\{\s*$', multiLine: true)
          .allMatches(gradle),
      hasLength(1),
    );

    final requiredPropertiesBlock = RegExp(
      r'^\s*val requiredReleaseSigningProperties\s*=\s*\n'
      r'\s*listOf\(([^)]*)\)\s*$',
      multiLine: true,
    ).firstMatch(gradle);
    expect(requiredPropertiesBlock, isNotNull);
    final requiredProperties = RegExp(r'"([^"]+)"')
        .allMatches(requiredPropertiesBlock!.group(1)!)
        .map((match) => match.group(1)!)
        .toSet();
    expect(
      requiredProperties,
      {'storeFile', 'storePassword', 'keyAlias', 'keyPassword'},
    );

    expect(
      RegExp(r'^\s*storeFile\s*=\s*releaseKeystoreFile\s*$', multiLine: true)
          .allMatches(gradle),
      hasLength(1),
    );
    for (final property in {'storePassword', 'keyAlias', 'keyPassword'}) {
      expect(
        RegExp(
          '^\\s*${RegExp.escape(property)}\\s*=\\s*'
          'releaseSigningProperties\\.getProperty\\("${RegExp.escape(property)}"\\)\\s*\$',
          multiLine: true,
        ).allMatches(gradle),
        hasLength(1),
      );
    }

    expect(
      RegExp(
        r'^\s*(?:storePassword|keyPassword)\s*=\s*"[^"]*"\s*$',
        multiLine: true,
      ).hasMatch(gradle),
      isFalse,
    );
    expect(
      RegExp(r'^\s*gradle\.taskGraph\.whenReady\b', multiLine: true)
          .hasMatch(gradle),
      isFalse,
    );
    expect(
      RegExp(
        r'^\s*tasks\.register<ValidateReleaseSigning>\("validateReleaseSigning"\)\s*\{\s*$',
        multiLine: true,
      ).allMatches(gradle),
      hasLength(1),
    );
    expect(
      RegExp(r'^\s*group\s*=\s*"verification"\s*$', multiLine: true)
          .allMatches(gradle),
      hasLength(1),
    );
    expect(
      RegExp(
        r'^\s*propertiesFile\.set\('
        r'rootProject\.layout\.projectDirectory\.file\("key\.properties"\)'
        r'\)\s*$',
        multiLine: true,
      ).allMatches(gradle),
      hasLength(1),
    );
    expect(
      RegExp(
        r'^\s*if\s*\(!configuredPropertiesFile\.isFile\)\s*\{\s*$',
        multiLine: true,
      ).allMatches(gradle),
      hasLength(1),
    );
    expect(
      RegExp(
        r'^\s*if\s*\(missingProperties\.isNotEmpty\(\)\)\s*\{\s*$',
        multiLine: true,
      ).allMatches(gradle),
      hasLength(1),
    );
    expect(
      RegExp(
        r'^\s*if\s*\(!configuredStoreFile\.isFile\)\s*\{\s*$',
        multiLine: true,
      ).allMatches(gradle),
      hasLength(1),
    );

    final releaseTaskPattern = RegExp(
      r'^\s*val releaseArtifactTaskName\s*=\s*'
      r'Regex\("\^\(assemble\|bundle\|package\)\.\*Release\.\*\$"\)\s*$',
      multiLine: true,
    );
    expect(releaseTaskPattern.allMatches(gradle), hasLength(1));
    expect(
      RegExp(
        r'^\s*dependsOn\(validateReleaseSigning\)\s*$',
        multiLine: true,
      ).allMatches(gradle),
      hasLength(1),
    );
    expect(
      RegExp(r'Regex\("[^"]*Debug[^"]*"\)').hasMatch(gradle),
      isFalse,
    );
  });
}

String _withoutMultilineComments(String contents) {
  return contents.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
}

Directory _findRepositoryRoot() {
  final startingDirectories = <Directory>{
    File.fromUri(Platform.script).parent.absolute,
    Directory.current.absolute,
  };

  for (final startingDirectory in startingDirectories) {
    var candidate = startingDirectory;

    while (true) {
      final pubspec = File('${candidate.path}/pubspec.yaml');
      if (pubspec.existsSync() &&
          RegExp(r'^name:\s*moms_ai\s*$', multiLine: true)
              .hasMatch(pubspec.readAsStringSync())) {
        return candidate;
      }

      final parent = candidate.parent;
      if (parent.path == candidate.path) {
        break;
      }
      candidate = parent;
    }
  }

  throw StateError('Unable to locate the moms_ai repository root.');
}
