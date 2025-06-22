import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class UrlCheckerService {
  static final String _apiKey = dotenv.env['GOOGLE_SAFE_BROWSING']!;

  static Future<bool> checkWithGoogleSafeBrowsing(String url) async {
    final endpoint =
        'https://safebrowsing.googleapis.com/v4/threatMatches:find?key=$_apiKey';

    final body = {
      "client": {"clientId": "watchtower-app", "clientVersion": "1.0"},
      "threatInfo": {
        "threatTypes": [
          "MALWARE",
          "SOCIAL_ENGINEERING",
          "UNWANTED_SOFTWARE",
          "POTENTIALLY_HARMFUL_APPLICATION",
        ],
        "platformTypes": ["ANY_PLATFORM"],
        "threatEntryTypes": ["URL"],
        "threatEntries": [
          {"url": url},
        ],
      },
    };

    final response = await http.post(
      Uri.parse(endpoint),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['matches'] != null && data['matches'].isNotEmpty;
    } else {
      throw Exception('Safe Browsing API failed: ${response.statusCode}');
    }
  }
}
