/// Domain model for an entry in the shared community scam database.
///
/// Pure Dart (no Flutter imports) so it stays testable and reusable. The
/// `fromDocument` factory understands Firestore's REST "Document" JSON shape,
/// where every field is wrapped in a typed value such as
/// `{"stringValue": "..."}` or `{"integerValue": "3"}`.

/// What kind of thing was reported.
enum ReportTarget {
  number,
  url;

  /// The Firestore collection that stores this kind of report.
  String get collection =>
      this == ReportTarget.number ? 'flagged_numbers' : 'flagged_urls';

  String get label => this == ReportTarget.number ? 'Number' : 'Link';
}

class CommunityReport {
  /// The reported value (a normalised phone number or a canonical URL).
  final String value;

  /// How many people have reported this value.
  final int reportCount;

  /// When it was last reported (UTC), if known.
  final DateTime? lastReportedAt;

  /// Optional short category describing the report.
  final String category;

  /// Whether this is a number or a URL report.
  final ReportTarget target;

  const CommunityReport({
    required this.value,
    required this.reportCount,
    required this.lastReportedAt,
    required this.category,
    required this.target,
  });

  /// Builds a [CommunityReport] from a Firestore REST `Document` object.
  factory CommunityReport.fromDocument(
    Map<String, dynamic> document,
    ReportTarget target,
  ) {
    final fields = (document['fields'] as Map?)?.cast<String, dynamic>() ?? {};
    return CommunityReport(
      value: _readString(fields['value']),
      reportCount: _readInt(fields['reportCount']),
      lastReportedAt: _readTimestamp(fields['lastReportedAt']),
      category: _readString(fields['category']),
      target: target,
    );
  }

  static String _readString(dynamic field) {
    if (field is Map && field['stringValue'] != null) {
      return field['stringValue'].toString();
    }
    return '';
  }

  static int _readInt(dynamic field) {
    if (field is Map) {
      final raw = field['integerValue'] ?? field['doubleValue'];
      if (raw is num) return raw.toInt();
      return int.tryParse('${raw ?? ''}') ?? 0;
    }
    return 0;
  }

  static DateTime? _readTimestamp(dynamic field) {
    if (field is Map && field['timestampValue'] != null) {
      return DateTime.tryParse(field['timestampValue'].toString());
    }
    return null;
  }
}
