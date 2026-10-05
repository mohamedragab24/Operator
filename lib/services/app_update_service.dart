import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateInfo {
  final int latestBuildNumber;
  final String versionName;
  final String apkUrl;
  final String releaseUrl;

  const AppUpdateInfo({
    required this.latestBuildNumber,
    required this.versionName,
    required this.apkUrl,
    required this.releaseUrl,
  });
}

/// Checks the latest Android release published by GitHub Actions.
///
/// GitHub Actions publishes every successful main-branch build as a GitHub
/// Release. The build number is the Actions run number, so every release has
/// a monotonically increasing versionCode.
class AppUpdateService {
  static const _owner = 'mohamedragab24';
  static const _repository = '-2';
  static const _latestReleaseApi =
      'https://api.github.com/repos/$_owner/$_repository/releases/latest';

  Future<AppUpdateInfo?> checkForAndroidUpdate() async {
    if (!Platform.isAndroid) return null;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final installedBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      final response = await http.get(
        Uri.parse(_latestReleaseApi),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = (json['tag_name'] ?? '').toString();
      final match = RegExp(r'^build-(\d+)$').firstMatch(tag);
      if (match == null) return null;

      final latestBuild = int.tryParse(match.group(1)!) ?? 0;
      if (latestBuild <= installedBuild) return null;

      final releaseUrl = (json['html_url'] ?? '').toString();
      final assets = (json['assets'] as List<dynamic>? ?? const []);
      String apkUrl = '';
      for (final raw in assets) {
        final asset = raw as Map<String, dynamic>;
        if ((asset['name'] ?? '').toString() == 'app-release.apk') {
          apkUrl = (asset['browser_download_url'] ?? '').toString();
          break;
        }
      }

      if (apkUrl.isEmpty) {
        apkUrl =
            'https://github.com/$_owner/$_repository/releases/latest/download/app-release.apk';
      }

      return AppUpdateInfo(
        latestBuildNumber: latestBuild,
        versionName: (json['name'] ?? tag).toString(),
        apkUrl: apkUrl,
        releaseUrl: releaseUrl,
      );
    } catch (_) {
      // Update checks must never prevent the app from opening.
      return null;
    }
  }

  Future<bool> openUpdate(AppUpdateInfo info) async {
    final uri = Uri.tryParse(info.apkUrl);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
