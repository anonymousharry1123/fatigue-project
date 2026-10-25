import 'dart:convert';
import 'dart:io';

Future<Map<String, dynamic>> postOura(
  Uri uri,
  String token,
  Map<String, Object?> body,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.postUrl(uri);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 45));
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) {
        throw const FormatException('Oura response is too large.');
      }
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid Oura response.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return {
        'error': value['error'] ?? {'code': 'provider_unavailable'},
      };
    }
    return value;
  } finally {
    client.close(force: true);
  }
}
