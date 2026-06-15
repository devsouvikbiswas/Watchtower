import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/community_report.dart';

/// Thrown when a community-database operation fails. The [message] is safe to
/// show directly to the user.
class CommunityDbException implements Exception {
  final String message;
  const CommunityDbException(this.message);

  @override
  String toString() => message;
}

/// Shared, cloud-backed scam database.
///
/// Lets every user contribute to and benefit from a single shared list of
/// reported scam numbers and links: when one person reports a value, everyone
/// who looks it up afterwards sees the warning ("reported by N people").
///
/// It talks directly to **Cloud Firestore via its REST API** using only the
/// `http` package. This deliberately avoids the `firebase_core` /
/// `cloud_firestore` native plugins, so the project needs no `flutterfire`
/// step, no `google-services.json`, and no Gradle changes — it builds in CI
/// exactly like before. Firestore's free (Spark) plan keeps it at zero cost.
///
/// Configuration comes from `.env`:
///   FIREBASE_PROJECT_ID  – your Firebase project id
///   FIREBASE_API_KEY     – the project's Web API key
/// See 3RD_FEATURE.md for how to obtain these.
class CommunityDbService {
  static String get _projectId =>
      dotenv.env['FIREBASE_PROJECT_ID']?.trim() ?? '';

  static String get _apiKey => dotenv.env['FIREBASE_API_KEY']?.trim() ?? '';

  /// Whether the community database has been configured. Callers can use this
  /// to degrade gracefully when Firebase keys are absent.
  static bool get isConfigured => _projectId.isNotEmpty && _apiKey.isNotEmpty;

  static String get _documentsBase =>
      'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents';

  static const Duration _timeout = Duration(seconds: 20);

  // --------------------------------------------------------------------------
  // Public API
  // --------------------------------------------------------------------------

  /// Reports a phone number as a scam, incrementing its community counter.
  static Future<void> reportNumber(
    String phone, {
    String category = 'User reported',
  }) {
    final normalized = _normalizePhone(phone);
    if (normalized.isEmpty) {
      throw const CommunityDbException('Enter a valid phone number to report.');
    }
    return _report(ReportTarget.number, normalized, normalized, category);
  }

  /// Reports a URL as a scam, incrementing its community counter.
  static Future<void> reportUrl(
    String url, {
    String category = 'User reported',
  }) {
    final canonical = _canonicalUrl(url);
    if (canonical.isEmpty) {
      throw const CommunityDbException('Enter a valid link to report.');
    }
    return _report(ReportTarget.url, _docIdForUrl(canonical), canonical, category);
  }

  /// Looks up a phone number. Returns `null` if nobody has reported it.
  static Future<CommunityReport?> lookupNumber(String phone) {
    final normalized = _normalizePhone(phone);
    if (normalized.isEmpty) return Future.value(null);
    return _getDocument(ReportTarget.number, normalized);
  }

  /// Looks up a URL. Returns `null` if nobody has reported it.
  static Future<CommunityReport?> lookupUrl(String url) {
    final canonical = _canonicalUrl(url);
    if (canonical.isEmpty) return Future.value(null);
    return _getDocument(ReportTarget.url, _docIdForUrl(canonical));
  }

  /// The most-reported entries of the given [target], highest count first.
  static Future<List<CommunityReport>> mostReported(
    ReportTarget target, {
    int limit = 20,
  }) {
    return _runTopQuery(target, limit);
  }

  // --------------------------------------------------------------------------
  // Firestore REST plumbing
  // --------------------------------------------------------------------------

  /// Atomically upserts the document and increments its `reportCount` by 1.
  static Future<void> _report(
    ReportTarget target,
    String docId,
    String value,
    String category,
  ) async {
    _ensureConfigured();

    final body = jsonEncode({
      'writes': [
        {
          'update': {
            'name':
                'projects/$_projectId/databases/(default)/documents/${target.collection}/$docId',
            'fields': {
              'value': {'stringValue': value},
              'category': {'stringValue': category},
              'lastReportedAt': {
                'timestampValue': DateTime.now().toUtc().toIso8601String(),
              },
            },
          },
          // Only touch these fields, so the existing reportCount is preserved
          // and the transform below increments it instead of overwriting it.
          'updateMask': {
            'fieldPaths': ['value', 'category', 'lastReportedAt'],
          },
          'updateTransforms': [
            {
              'fieldPath': 'reportCount',
              'increment': {'integerValue': '1'},
            },
          ],
        },
      ],
    });

    final uri = Uri.parse(
      '$_documentsBase:commit',
    ).replace(queryParameters: {'key': _apiKey});

    final response = await _post(uri, body);
    if (response.statusCode != 200) {
      throw CommunityDbException(_describeHttpError(response));
    }
  }

  static Future<CommunityReport?> _getDocument(
    ReportTarget target,
    String docId,
  ) async {
    _ensureConfigured();

    final uri = Uri.parse(
      '$_documentsBase/${target.collection}/$docId',
    ).replace(queryParameters: {'key': _apiKey});

    late final http.Response response;
    try {
      response = await http.get(uri).timeout(_timeout);
    } catch (_) {
      throw const CommunityDbException(
        'Could not reach the community database. Check your connection.',
      );
    }

    if (response.statusCode == 404) return null; // No reports for this value.
    if (response.statusCode != 200) {
      throw CommunityDbException(_describeHttpError(response));
    }

    try {
      final doc = jsonDecode(response.body) as Map<String, dynamic>;
      return CommunityReport.fromDocument(doc, target);
    } catch (_) {
      throw const CommunityDbException(
        'The community database returned an unexpected response.',
      );
    }
  }

  static Future<List<CommunityReport>> _runTopQuery(
    ReportTarget target,
    int limit,
  ) async {
    _ensureConfigured();

    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': target.collection},
        ],
        'orderBy': [
          {
            'field': {'fieldPath': 'reportCount'},
            'direction': 'DESCENDING',
          },
        ],
        'limit': limit,
      },
    });

    final uri = Uri.parse(
      '$_documentsBase:runQuery',
    ).replace(queryParameters: {'key': _apiKey});

    final response = await _post(uri, body);
    if (response.statusCode != 200) {
      throw CommunityDbException(_describeHttpError(response));
    }

    try {
      final rows = jsonDecode(response.body) as List<dynamic>;
      final reports = <CommunityReport>[];
      for (final row in rows) {
        // runQuery streams an array; rows without a `document` (e.g. the
        // initial readTime marker) are skipped.
        final doc = (row is Map) ? row['document'] : null;
        if (doc is Map<String, dynamic>) {
          reports.add(CommunityReport.fromDocument(doc, target));
        }
      }
      return reports;
    } catch (_) {
      throw const CommunityDbException(
        'The community database returned an unexpected response.',
      );
    }
  }

  static Future<http.Response> _post(Uri uri, String body) async {
    try {
      return await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(_timeout);
    } catch (_) {
      throw const CommunityDbException(
        'Could not reach the community database. Check your connection.',
      );
    }
  }

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------

  static void _ensureConfigured() {
    if (!isConfigured) {
      throw const CommunityDbException(
        'Community database is not configured. Set FIREBASE_PROJECT_ID and '
        'FIREBASE_API_KEY (see 3RD_FEATURE.md).',
      );
    }
  }

  static String _normalizePhone(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9]'), '');

  /// Produces a stable, comparable form of a URL so the same link always maps
  /// to the same document regardless of casing or a trailing slash.
  static String _canonicalUrl(String raw) {
    var input = raw.trim();
    if (input.isEmpty) return '';
    if (!input.startsWith('http://') && !input.startsWith('https://')) {
      input = 'https://$input';
    }
    final uri = Uri.tryParse(input);
    if (uri == null || uri.host.isEmpty) return raw.trim().toLowerCase();

    var path = uri.path;
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return '${uri.host.toLowerCase()}$path$query';
  }

  /// A Firestore-document-id-safe key for a URL. base64url uses only
  /// `A-Z a-z 0-9 - _`, none of which are illegal in a document id.
  static String _docIdForUrl(String canonicalUrl) =>
      base64Url.encode(utf8.encode(canonicalUrl)).replaceAll('=', '');

  static String _describeHttpError(http.Response response) {
    String? apiMessage;
    try {
      apiMessage = jsonDecode(response.body)?['error']?['message']?.toString();
    } catch (_) {
      apiMessage = null;
    }

    switch (response.statusCode) {
      case 400:
        return 'The community database rejected the request'
            '${apiMessage != null ? ': $apiMessage' : '.'}';
      case 401:
      case 403:
        return 'Community database access was denied. Check the Firestore '
            'security rules and FIREBASE_API_KEY (see 3RD_FEATURE.md).';
      case 429:
        return 'Community database is busy (rate limit). Try again shortly.';
      case 500:
      case 503:
        return 'Community database is temporarily unavailable. Try again soon.';
      default:
        return 'Community database request failed (HTTP ${response.statusCode})'
            '${apiMessage != null ? ': $apiMessage' : '.'}';
    }
  }
}
