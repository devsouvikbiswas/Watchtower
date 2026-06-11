import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/scam_analysis.dart';

/// Thrown when the scam detector cannot produce a result. The [message] is
/// safe to show directly to the user.
class ScamDetectorException implements Exception {
  final String message;
  const ScamDetectorException(this.message);

  @override
  String toString() => message;
}

/// Analyses free-text messages (SMS / WhatsApp / email) for scam and phishing
/// content using Google's Gemini API.
///
/// Gemini is used because it has a genuinely free tier (an API key from
/// Google AI Studio requires no billing account), which keeps the project at
/// zero cost. The request uses Gemini's structured-output feature
/// (`responseMimeType: application/json` + `responseSchema`) so the reply is
/// always valid JSON we can parse reliably.
class ScamDetectorService {
  /// The Gemini model to use. Overridable via `.env` so it can be changed
  /// without touching code; defaults to the fast, free `gemini-2.0-flash`.
  static String get _model =>
      (dotenv.env['GEMINI_MODEL']?.trim().isNotEmpty ?? false)
      ? dotenv.env['GEMINI_MODEL']!.trim()
      : 'gemini-2.0-flash';

  static String get _apiKey => dotenv.env['GEMINI_API_KEY']?.trim() ?? '';

  /// Instructions that define the detector's behaviour and output contract.
  static const String _systemPrompt = '''
You are "Watchtower", a fraud-detection assistant for Indian users. You analyse
an SMS, WhatsApp message, or email and decide whether it is a scam.

You understand the scams common in India: fake bank/KYC updates, UPI and OTP
fraud, lottery/prize wins, fake job and loan offers, electricity-bill
disconnection threats, parcel/courier scams, "your account is blocked" phishing,
and fake government messages.

Judge the message using signals such as: artificial urgency and threats,
requests for OTP/PIN/card/UPI details, shortened or look-alike links, demands
for an up-front payment or "processing fee", impersonation of a bank or
government body, and prizes the recipient never entered for.

Return ONLY a JSON object with these fields:
- "risk": integer 0-100 (0 = clearly safe, 100 = certainly a scam).
- "verdict": one of "SAFE", "SUSPICIOUS", "SCAM".
- "category": short label for the scam type, or the message type if legitimate.
- "red_flags": array of the exact phrases copied verbatim from the message that
  are suspicious. Copy them character-for-character so they can be highlighted.
  Use an empty array if the message is genuinely safe.
- "explanation_en": 1-3 sentences, plain English, explaining the verdict so a
  non-technical person understands.
- "explanation_bn": the same explanation written in Bengali (বাংলা).
- "advice": one short actionable instruction (e.g. "Do not click the link or
  share any OTP.").

Be decisive but fair: do not flag ordinary personal or transactional messages.
''';

  /// JSON schema Gemini must conform its response to.
  static const Map<String, dynamic> _responseSchema = {
    'type': 'OBJECT',
    'properties': {
      'risk': {'type': 'INTEGER'},
      'verdict': {'type': 'STRING'},
      'category': {'type': 'STRING'},
      'red_flags': {
        'type': 'ARRAY',
        'items': {'type': 'STRING'},
      },
      'explanation_en': {'type': 'STRING'},
      'explanation_bn': {'type': 'STRING'},
      'advice': {'type': 'STRING'},
    },
    'required': [
      'risk',
      'verdict',
      'category',
      'red_flags',
      'explanation_en',
      'explanation_bn',
      'advice',
    ],
    'propertyOrdering': [
      'risk',
      'verdict',
      'category',
      'red_flags',
      'explanation_en',
      'explanation_bn',
      'advice',
    ],
  };

  /// Analyses [message] and returns a [ScamAnalysis].
  ///
  /// Throws a [ScamDetectorException] with a user-facing message on any failure
  /// (missing key, network error, blocked content, bad response).
  static Future<ScamAnalysis> analyze(String message) async {
    final text = message.trim();
    if (text.isEmpty) {
      throw const ScamDetectorException('Please paste a message to analyse.');
    }
    if (_apiKey.isEmpty) {
      throw const ScamDetectorException(
        'AI key is not configured. Set GEMINI_API_KEY in the build '
        'environment (see SETUP_GUIDE.md).',
      );
    }

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent',
    );

    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': _systemPrompt},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': 'Analyse this message:\n\n"""\n$text\n"""'},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.2,
        'responseMimeType': 'application/json',
        'responseSchema': _responseSchema,
      },
    });

    late final http.Response response;
    try {
      response = await http
          .post(
            uri,
            // Gemini accepts the key via header or query param; the header
            // keeps it out of the request URL / logs.
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': _apiKey,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw const ScamDetectorException(
        'Could not reach the AI service. Check your internet connection and '
        'try again.',
      );
    }

    if (response.statusCode != 200) {
      throw ScamDetectorException(_describeHttpError(response));
    }

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const ScamDetectorException(
        'The AI service returned an unexpected response. Try again.',
      );
    }

    // Gemini can refuse to answer and return a blockReason instead of content.
    final blockReason = decoded['promptFeedback']?['blockReason'];
    if (blockReason != null) {
      throw ScamDetectorException(
        'The AI service blocked this content ($blockReason). Try a different '
        'message.',
      );
    }

    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const ScamDetectorException(
        'The AI service did not return a result. Please try again.',
      );
    }

    final parts = candidates.first?['content']?['parts'];
    final rawText = (parts is List && parts.isNotEmpty)
        ? parts.first?['text']?.toString()
        : null;
    if (rawText == null || rawText.trim().isEmpty) {
      throw const ScamDetectorException(
        'The AI service returned an empty result. Please try again.',
      );
    }

    try {
      final analysisJson = jsonDecode(rawText) as Map<String, dynamic>;
      return ScamAnalysis.fromJson(analysisJson);
    } catch (_) {
      throw const ScamDetectorException(
        'Could not understand the AI response. Please try again.',
      );
    }
  }

  /// Turns a non-200 Gemini response into a friendly, specific message.
  static String _describeHttpError(http.Response response) {
    String? apiMessage;
    try {
      apiMessage = jsonDecode(response.body)?['error']?['message']?.toString();
    } catch (_) {
      apiMessage = null;
    }

    switch (response.statusCode) {
      case 400:
        return 'The request was rejected by the AI service'
            '${apiMessage != null ? ': $apiMessage' : '.'}';
      case 401:
      case 403:
        return 'The AI key was rejected. Check that GEMINI_API_KEY is valid '
            'and the Generative Language API is enabled.';
      case 429:
        return 'AI free-tier rate limit reached. Wait a minute and try again.';
      case 500:
      case 503:
        return 'The AI service is temporarily unavailable. Try again shortly.';
      default:
        return 'AI request failed (HTTP ${response.statusCode})'
            '${apiMessage != null ? ': $apiMessage' : '.'}';
    }
  }
}
