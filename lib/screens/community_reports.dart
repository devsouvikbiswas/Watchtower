import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/community_report.dart';
import '../services/community_db_service.dart';

/// The shared community scam database screen.
///
/// Users can check whether a number or link has been reported by others
/// ("reported by N people"), add their own report, and see the most-reported
/// entries — all stored in the cloud and shared across every install.
class CommunityReportsPage extends StatefulWidget {
  const CommunityReportsPage({super.key});

  @override
  State<CommunityReportsPage> createState() => _CommunityReportsPageState();
}

class _CommunityReportsPageState extends State<CommunityReportsPage> {
  final TextEditingController _controller = TextEditingController();

  ReportTarget _target = ReportTarget.number;

  bool _isChecking = false;
  bool _isReporting = false;
  String? _error;

  // Lookup state: whether a lookup has completed, and its result (null = the
  // value has no community reports yet).
  bool _hasLookedUp = false;
  CommunityReport? _lookupResult;
  String _lookedUpValue = '';

  late Future<List<CommunityReport>> _topFuture;

  @override
  void initState() {
    super.initState();
    _topFuture = _loadTop();
  }

  Future<List<CommunityReport>> _loadTop() {
    if (!CommunityDbService.isConfigured) {
      return Future.value(const []);
    }
    return CommunityDbService.mostReported(_target, limit: 25);
  }

  void _refreshTop() {
    setState(() => _topFuture = _loadTop());
  }

  Future<void> _check() async {
    final input = _controller.text.trim();
    if (input.isEmpty) {
      setState(() => _error = 'Enter a number or link to check.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isChecking = true;
      _error = null;
      _hasLookedUp = false;
      _lookupResult = null;
    });

    try {
      final report = _target == ReportTarget.number
          ? await CommunityDbService.lookupNumber(input)
          : await CommunityDbService.lookupUrl(input);
      if (!mounted) return;
      setState(() {
        _lookupResult = report;
        _hasLookedUp = true;
        _lookedUpValue = input;
      });
    } on CommunityDbException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _report() async {
    final input = _controller.text.trim();
    if (input.isEmpty) {
      setState(() => _error = 'Enter a number or link to report.');
      return;
    }

    setState(() {
      _isReporting = true;
      _error = null;
    });

    try {
      if (_target == ReportTarget.number) {
        await CommunityDbService.reportNumber(input);
      } else {
        await CommunityDbService.reportUrl(input);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reported to the community. Thank you!')),
      );
      // Re-check so the new count shows immediately, and refresh the top list.
      await _check();
      _refreshTop();
    } on CommunityDbException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _isReporting = false);
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      _controller.text = text;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: text.length),
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
    final busy = _isChecking || _isReporting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Community Scam DB'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh list',
            onPressed: _refreshTop,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refreshTop(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!CommunityDbService.isConfigured) _notConfiguredBanner(),
            const Text(
              'Check if a number or link has been reported as a scam by other '
              'people — and add your own report to protect everyone.',
              style: TextStyle(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            _targetSelector(busy),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              keyboardType: _target == ReportTarget.number
                  ? TextInputType.phone
                  : TextInputType.url,
              decoration: InputDecoration(
                labelText: _target == ReportTarget.number
                    ? 'Phone number'
                    : 'Link / URL',
                hintText: _target == ReportTarget.number
                    ? 'e.g. 9876543210'
                    : 'e.g. bit.ly/abcd',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste),
                  onPressed: busy ? null : _paste,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: busy ? null : _check,
                    icon: _isChecking
                        ? const _ButtonSpinner()
                        : const Icon(Icons.search),
                    label: const Text('Check'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: busy ? null : _report,
                    icon: _isReporting
                        ? const _ButtonSpinner()
                        : const Icon(Icons.flag),
                    label: const Text('Report'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_error != null) _errorCard(_error!),
            if (_hasLookedUp) _lookupCard(),
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(Icons.public, size: 18, color: Colors.white60),
                const SizedBox(width: 8),
                Text(
                  'Most reported ${_target.label.toLowerCase()}s',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _topList(),
          ],
        ),
      ),
    );
  }

  Widget _targetSelector(bool busy) {
    return Wrap(
      spacing: 8,
      children: ReportTarget.values.map((t) {
        return ChoiceChip(
          label: Text(t.label),
          selected: _target == t,
          onSelected: busy
              ? null
              : (_) {
                  setState(() {
                    _target = t;
                    _hasLookedUp = false;
                    _lookupResult = null;
                    _error = null;
                  });
                  _refreshTop();
                },
        );
      }).toList(),
    );
  }

  Widget _lookupCard() {
    final report = _lookupResult;
    final count = report?.reportCount ?? 0;
    final reported = count > 0;
    final color = reported
        ? const Color(0xFFD7443B)
        : const Color(0xFF2E9E5B);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                reported ? Icons.dangerous : Icons.verified_user,
                color: color,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  reported
                      ? 'Reported by $count ${count == 1 ? 'person' : 'people'}'
                      : 'No community reports yet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _lookedUpValue,
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          if (reported && report?.lastReportedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Last reported ${_formatDate(report!.lastReportedAt!)}',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
          if (!reported) ...[
            const SizedBox(height: 8),
            const Text(
              'If you believe this is a scam, tap Report to warn others.',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  Widget _topList() {
    return FutureBuilder<List<CommunityReport>>(
      future: _topFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return _errorCard(
            snapshot.error is CommunityDbException
                ? (snapshot.error as CommunityDbException).message
                : 'Could not load the community list.',
          );
        }
        final reports = snapshot.data ?? const [];
        if (reports.isEmpty) {
          return Card(
            color: const Color(0xFF24242F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No reports yet. Be the first to make the community safer.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          );
        }
        return Column(
          children: reports.map(_topTile).toList(),
        );
      },
    );
  }

  Widget _topTile(CommunityReport report) {
    return Card(
      color: const Color(0xFF24242F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.red.shade700,
          child: Text(
            '${report.reportCount}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        title: Text(
          report.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          report.lastReportedAt != null
              ? '${report.category} • last ${_formatDate(report.lastReportedAt!)}'
              : report.category,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.flag, color: Colors.redAccent),
        onTap: () {
          _controller.text = report.value;
          _check();
        },
      ),
    );
  }

  Widget _notConfiguredBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3A3320),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade700),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.amber),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Community database is not configured yet. Add FIREBASE_PROJECT_ID '
              'and FIREBASE_API_KEY (see 3RD_FEATURE.md) to enable it.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    return '$d/$m/${local.year}';
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
  }
}
