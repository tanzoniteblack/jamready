import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:jam_ready/screens/about_screen.dart';
import 'package:jam_ready/screens/app_home_screen.dart';

void main() {
  group('formatAppVersion', () {
    test('includes build number for non-release builds', () {
      expect(formatAppVersion('2.0.0', '8', isRelease: false), '2.0.0+8');
    });

    test('omits build number for release builds', () {
      expect(formatAppVersion('2.0.0', '8', isRelease: true), '2.0.0');
    });

    test('omits empty build number', () {
      expect(formatAppVersion('1.2.0', '', isRelease: false), '1.2.0');
    });

    test('shows the release tag without its leading v', () {
      expect(
        formatAppVersion('2.0.0', '9', isRelease: true, tag: 'v2.0.0-beta3'),
        '2.0.0-beta3',
      );
    });

    test('shows a stable release tag as the plain version', () {
      expect(
        formatAppVersion('2.0.0', '10', isRelease: true, tag: 'v2.0.0'),
        '2.0.0',
      );
    });
  });

  testWidgets('info button on home screen opens About page', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'JamReady',
      packageName: 'net.jamready',
      version: '2.0.0',
      buildNumber: '8',
      buildSignature: '',
    );

    await tester.pumpWidget(const MaterialApp(home: AppHomeScreen()));
    await tester.tap(find.byTooltip('About'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.text('2.0.0+8'), findsOneWidget);
    expect(find.text(developerCredit), findsOneWidget);
    expect(find.text(contactEmail), findsOneWidget);
  });

  testWidgets('tapping version copies it to the clipboard', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'JamReady',
      packageName: 'net.jamready',
      version: '2.0.0',
      buildNumber: '8',
      buildSignature: '',
    );
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );

    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2.0.0+8'));
    await tester.pump();

    expect(copied, '2.0.0+8');
    expect(find.text('Copied version 2.0.0+8'), findsOneWidget);
  });
}
