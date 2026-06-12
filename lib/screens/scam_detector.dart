import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/scam_analysis.dart';
import '../services/scam_detector_service.dart';

/// Screen that lets the user paste a suspicious SMS / WhatsApp / email message
/// and get an AI-powered verdict explaining whether it is a scam and why.
class ScamDetectorPage extends StatefulWidget {
  const ScamDetectorPage({super.key});

  @override
  State<ScamDetectorPage> createState() => _ScamDetectorPageState();
}

class _ScamDetectorPageState extends State<ScamDetectorPage> {
  final TextEditingController _controller = TextEditingController();

  bool _isLoading = false;
  String? _error;
  ScamAnalysis? _result;

  // The message that produced [_result], kept so red-flag highlighting always
  // matches the analysed text even if the input box changes afterwards.
  String _analysedText = '';

  Future<void> _analyze() async {
    final message = _controller.text.trim();
    if (message.isEmpty) {
      setState(() => _error = 'Please paste a message to analyse.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    try {
      final analysis = await ScamDetectorService.analyze(message);
      if (!mounted) return;
      setState(() {
        _result = analysis;
        _analysedText = message;
      });
    } on ScamDetectorException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      _controller.text = text;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: text.length),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard is empty.')),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scam Detector')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Paste any suspicious SMS, WhatsApp or email message and the AI '
              'will tell you if it is a scam — and explain why.',
              style: TextStyle(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLines: 6,
              minLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                labelText: 'Message to check',
                hintText:
                    'e.g. Dear customer, your KYC has expired. Click '
                    'http://bit.ly/xx to update or your account will be blocked.',
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Paste from clipboard',
                  icon: const Icon(Icons.content_paste),
                  onPressed: _isLoading ? null : _pasteFromClipboard,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _analyze,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.shield),
              label: Text(_isLoading ? 'Analysing…' : 'Analyse message'),
            ),
            const SizedBox(height: 20),
            if (_error != null) _ErrorCard(message: _error!, onRetry: _analyze),
            if (_result != null)
              _ResultView(analysis: _result!, originalText: _analysedText),
          ],
        ),
      ),
    );
  }
}

/// Maps a verdict + risk to the colour used throughout the result UI.
Color _riskColor(ScamAnalysis analysis) {
  switch (analysis.verdict) {
    case ScamVerdict.safe:
      return const Color(0xFF2E9E5B);
    case ScamVerdict.suspicious:
      return const Color(0xFFE0902C);
    case ScamVerdict.scam:
      return const Color(0xFFD7443B);
    case ScamVerdict.unknown:
      return analysis.risk >= 50
          ? const Color(0xFFD7443B)
          : const Color(0xFFE0902C);
  }
}

IconData _verdictIcon(ScamVerdict verdict) {
  switch (verdict) {
    case ScamVerdict.safe:
      return Icons.verified_user;
    case ScamVerdict.suspicious:
      return Icons.warning_amber_rounded;
    case ScamVerdict.scam:
      return Icons.dangerous;
    case ScamVerdict.unknown:
      return Icons.help_outline;
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF3A2A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 14)),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  final ScamAnalysis analysis;
  final String originalText;

  const _ResultView({required this.analysis, required this.originalText});

  @override
  Widget build(BuildContext context) {
    final color = _riskColor(analysis);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _verdictHeader(color),
        const SizedBox(height: 16),
        _riskMeter(color),
        const SizedBox(height: 20),
        if (analysis.redFlags.isNotEmpty) ...[
          _sectionTitle('Message (suspicious parts highlighted)'),
          const SizedBox(height: 8),
          _highlightedMessage(color),
          const SizedBox(height: 20),
          _sectionTitle('Red flags'),
          const SizedBox(height: 8),
          _redFlagChips(color),
          const SizedBox(height: 20),
        ],
        _sectionTitle('Why'),
        const SizedBox(height: 8),
        if (analysis.explanationEn.isNotEmpty)
          Text(analysis.explanationEn, style: const TextStyle(fontSize: 15)),
        if (analysis.explanationBn.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            analysis.explanationBn,
            style: const TextStyle(fontSize: 15, color: Colors.white70),
          ),
        ],
        if (analysis.advice.isNotEmpty) ...[
          const SizedBox(height: 20),
          _adviceBanner(color),
        ],
      ],
    );
  }

  Widget _verdictHeader(Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(_verdictIcon(analysis.verdict), color: color, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  analysis.verdict.label,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  analysis.category,
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _riskMeter(Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Risk score', style: TextStyle(fontSize: 14)),
            Text(
              '${analysis.risk}/100',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: analysis.risk / 100,
            minHeight: 12,
            backgroundColor: const Color(0xFF3A3A4A),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _highlightedMessage(Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF24242F),
        borderRadius: BorderRadius.circular(12),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 15, color: Colors.white, height: 1.4),
          children: _buildHighlightSpans(originalText, analysis.redFlags, color),
        ),
      ),
    );
  }

  Widget _redFlagChips(Color color) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: analysis.redFlags
          .map(
            (flag) => Chip(
              label: Text(flag),
              backgroundColor: color.withValues(alpha: 0.18),
              side: BorderSide(color: color.withValues(alpha: 0.6)),
              labelStyle: const TextStyle(fontSize: 13),
            ),
          )
          .toList(),
    );
  }

  Widget _adviceBanner(Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.tips_and_updates, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              analysis.advice,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
        color: Colors.white60,
      ),
    );
  }
}

/// Splits [text] into highlighted (matched red flag) and normal spans.
/// Matching is case-insensitive and picks the earliest match at each position
/// so overlapping flags don't break the layout.
List<TextSpan> _buildHighlightSpans(
  String text,
  List<String> flags,
  Color color,
) {
  final phrases = flags
      .map((f) => f.trim())
      .where((f) => f.isNotEmpty)
      .toList();
  if (phrases.isEmpty) {
    return [TextSpan(text: text)];
  }

  final lowerText = text.toLowerCase();
  final spans = <TextSpan>[];
  var index = 0;

  while (index < text.length) {
    int matchStart = -1;
    int matchLength = 0;

    // Find the earliest-starting flag from the current position.
    for (final phrase in phrases) {
      final found = lowerText.indexOf(phrase.toLowerCase(), index);
      if (found != -1 && (matchStart == -1 || found < matchStart)) {
        matchStart = found;
        matchLength = phrase.length;
      }
    }

    if (matchStart == -1) {
      spans.add(TextSpan(text: text.substring(index)));
      break;
    }

    if (matchStart > index) {
      spans.add(TextSpan(text: text.substring(index, matchStart)));
    }

    spans.add(
      TextSpan(
        text: text.substring(matchStart, matchStart + matchLength),
        style: TextStyle(
          backgroundColor: color.withValues(alpha: 0.30),
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    index = matchStart + matchLength;
  }

  return spans;
}
