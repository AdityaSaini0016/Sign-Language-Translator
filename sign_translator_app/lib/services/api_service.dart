import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiService {
  static const String _defaultBaseUrl =
      'https://sign-language-translator-587v.onrender.com';
  static const String _configuredBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: _defaultBaseUrl);

  static String get baseUrl => _configuredBaseUrl;

  static Uri _translateUri() => Uri.parse('$_configuredBaseUrl/translate');

  static Future<Map<String, dynamic>> translateSignLanguage(
    String imagePath,
  ) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        _translateUri(),
      );

      request.files.add(await http.MultipartFile.fromPath('file', imagePath));

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 10),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        return {
          'text': data['text'] ?? 'Unknown',
          'confidence': (data['confidence'] ?? 0.0).toDouble(),
          'error': data['error'],
        };
      }

      return {
        'text': 'Server Error (${response.statusCode})',
        'confidence': 0.0,
        'error': response.body,
      };
    } catch (e) {
      return {
        'text': 'Connection issue',
        'confidence': 0.0,
        'error': e.toString(),
      };
    }
  }
}
