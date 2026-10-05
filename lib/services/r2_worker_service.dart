import 'dart:convert';
import 'package:http/http.dart' as http;

class R2WorkerService {
  static const String _defaultWorkerUrl = 'https://fahmny-r2.mohamedragabewiess.workers.dev';

  static String get workerUrl {
    const configured = String.fromEnvironment('R2_WORKER_URL');
    return configured.trim().isEmpty ? _defaultWorkerUrl : configured.trim();
  }

  static String keyToUrl(String key) {
    final clean = key.replaceFirst(RegExp(r'^/+'), '');
    final encoded = clean.split('/').map(Uri.encodeComponent).join('/');
    return '${workerUrl.replaceFirst(RegExp(r'/+$'), '')}/$encoded';
  }

  static Future<Map<String, dynamic>?> getJson(String key) async {
    try {
      final response = await http.get(Uri.parse(keyToUrl(key)));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static String? tokenToUrl(String token) {
    final value = token.trim();
    if (value.startsWith('r2:')) {
      final parts = value.split(':');
      if (parts.length >= 4) return keyToUrl(parts.sublist(3).join(':'));
    }
    if (value.startsWith('r2cover:')) {
      final parts = value.split(':');
      if (parts.length >= 3) return keyToUrl(parts.sublist(2).join(':'));
    }
    return null;
  }
}
