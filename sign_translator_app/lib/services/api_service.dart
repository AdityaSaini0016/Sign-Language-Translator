import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // 🔥 Replace with your laptop IP
  static const String _baseUrl = "https://sign-language-translator-1-x21g.onrender.com";

  // Returns structured data (text + confidence)
  static Future<Map<String, dynamic>> translateSignLanguage(String imagePath) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/translate'),
      );

      // Attach image file
      request.files.add(await http.MultipartFile.fromPath('file', imagePath));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        return {
          "text": data['text'] ?? "Unknown",
          "confidence": (data['confidence'] ?? 0.0).toDouble(),
        };
      } else {
        return {
          "text": "Server Error (${response.statusCode})",
          "confidence": 0.0,
        };
      }
    } catch (e) {
      return {
        "text": "Error: $e",
        "confidence": 0.0,
      };
    }
  }
}