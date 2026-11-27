import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../styles/background.dart';

const contactEmail = 'info@jamready.net';
const developerCredit = 'Smithsonian (Ryan Smith)';

/// The git tag this build was cut from (e.g. "v2.0.0-beta3"), injected with
/// `--dart-define=RELEASE_TAG=<tag>` by the release builds. Empty otherwise.
const releaseTag = String.fromEnvironment('RELEASE_TAG');

/// Tagged builds show the tag without its leading "v" (e.g. "2.0.0-beta3"),
/// other release builds show only the marketing version (e.g. "2.0.0"), and
/// local/debug builds include the build number (e.g. "2.0.0+8").
String formatAppVersion(
  String version,
  String buildNumber, {
  bool isRelease = kReleaseMode,
  String tag = releaseTag,
}) => switch (tag) {
  final t when t.isNotEmpty => t.replaceFirst(RegExp('^v'), ''),
  _ when isRelease || buildNumber.isEmpty => version,
  _ => '$version+$buildNumber',
};

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<String> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    return formatAppVersion(info.version, info.buildNumber);
  }

  Future<void> _copyVersion(BuildContext context, String version) async {
    await Clipboard.setData(ClipboardData(text: version));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Copied version $version')));
  }

  @override
  Widget build(BuildContext context) {
    return DynamicBackground(
      accentColor: Colors.deepOrange.shade400,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('About'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Text(
                'JAMREADY',
                style: TextStyle(
                  color: Colors.deepOrange.shade200,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.9,
                ),
              ),
              const SizedBox(height: 14),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.045),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Column(
                  children: [
                    FutureBuilder<String>(
                      future: _loadVersion(),
                      builder: (context, snapshot) => _AboutRow(
                        label: 'VERSION',
                        value: snapshot.data ?? '…',
                        onTap: switch (snapshot.data) {
                          final version? => () => _copyVersion(
                            context,
                            version,
                          ),
                          null => null,
                        },
                      ),
                    ),
                    const _RowDivider(),
                    const _AboutRow(
                      label: 'DEVELOPED BY',
                      value: developerCredit,
                    ),
                    const _RowDivider(),
                    _AboutRow(
                      label: 'CONTACT',
                      value: contactEmail,
                      valueColor: Colors.deepOrange.shade200,
                      onTap: () =>
                          launchUrl(Uri(scheme: 'mailto', path: contactEmail)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: Colors.white.withValues(alpha: 0.09));
}

class _AboutRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final VoidCallback? onTap;

  const _AboutRow({
    required this.label,
    required this.value,
    this.valueColor = Colors.white,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.52),
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: Text(
                value,
                style: TextStyle(
                  color: valueColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
