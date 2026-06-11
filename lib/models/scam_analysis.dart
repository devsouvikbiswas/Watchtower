/// Domain model for the result of analysing a message with the AI scam
/// detector. This is a pure-Dart model (no Flutter imports) so it can be unit
/// tested and reused independently of the UI layer.

/// The overall verdict the detector assigns to a message.
enum ScamVerdict {
  safe,
  suspicious,
  scam,
  unknown;

  /// Maps a raw verdict string returned by the model to a [ScamVerdict].
  static ScamVerdict fromString(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'SAFE':
        return ScamVerdict.safe;
      case 'SUSPICIOUS':
        return ScamVerdict.suspicious;
      case 'SCAM':
        return ScamVerdict.scam;
      default:
        return ScamVerdict.unknown;
    }
  }

  /// Human-readable label shown in the UI.
  String get label {
    switch (this) {
      case ScamVerdict.safe:
        return 'Looks Safe';
      case ScamVerdict.suspicious:
        return 'Suspicious';
      case ScamVerdict.scam:
        return 'Scam Detected';
      case ScamVerdict.unknown:
        return 'Unclear';
    }
  }
}

class ScamAnalysis {
  /// Risk score from 0 (safe) to 100 (definitely a scam).
  final int risk;

  /// The overall verdict.
  final ScamVerdict verdict;

  /// Short category describing the type of scam, e.g. "KYC / phishing",
  /// "Lottery scam", "Fake job offer". For legitimate messages this describes
  /// the message type instead.
  final String category;

  /// The exact phrases from the original message that triggered the verdict.
  /// These are highlighted back inside the user's message in the UI.
  final List<String> redFlags;

  /// Plain-language explanation in English of why this verdict was reached.
  final String explanationEn;

  /// The same explanation in Bengali, so non-English speakers understand.
  final String explanationBn;

  /// A short, actionable piece of advice ("Do not click the link", etc.).
  final String advice;

  const ScamAnalysis({
    required this.risk,
    required this.verdict,
    required this.category,
    required this.redFlags,
    required this.explanationEn,
    required this.explanationBn,
    required this.advice,
  });

  /// Builds a [ScamAnalysis] from the JSON object the Gemini model returns.
  ///
  /// The model is instructed (and constrained by a response schema) to return
  /// these exact fields, but we still parse defensively so a slightly
  /// malformed payload degrades gracefully instead of crashing.
  factory ScamAnalysis.fromJson(Map<String, dynamic> json) {
    final rawRisk = json['risk'];
    int risk;
    if (rawRisk is int) {
      risk = rawRisk;
    } else if (rawRisk is num) {
      risk = rawRisk.round();
    } else {
      risk = int.tryParse('${rawRisk ?? ''}') ?? 0;
    }
    if (risk < 0) risk = 0;
    if (risk > 100) risk = 100;

    final rawFlags = json['red_flags'];
    final redFlags = (rawFlags is List)
        ? rawFlags
              .map((e) => e?.toString().trim() ?? '')
              .where((e) => e.isNotEmpty)
              .toList()
        : <String>[];

    return ScamAnalysis(
      risk: risk,
      verdict: ScamVerdict.fromString(json['verdict']?.toString()),
      category: (json['category']?.toString().trim().isNotEmpty ?? false)
          ? json['category'].toString().trim()
          : 'Unknown',
      redFlags: redFlags,
      explanationEn: json['explanation_en']?.toString().trim() ?? '',
      explanationBn: json['explanation_bn']?.toString().trim() ?? '',
      advice: json['advice']?.toString().trim() ?? '',
    );
  }
}
