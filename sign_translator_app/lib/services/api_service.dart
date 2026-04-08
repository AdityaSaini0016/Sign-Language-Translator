import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Use 10.0.2.2 for Android Emulator, or your Local IP for real devices
  static const String _baseUrl = "http://192.168.29.8:8000";

  // Renamed to match your CameraScreen call and added 'static'
  static Future<String> translateSignLanguage(String imagePath) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/translate'));
      
      // Attach the image file
      request.files.add(await http.MultipartFile.fromPath('file', imagePath));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return data['text'] ?? "Unknown";
      } else {
        return "Server Error: ${response.statusCode}";
      }
    } catch (e) {
      return "Connection Failed: $e";
    }
  }
}