import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import '../services/url_checker_service.dart';
import 'sandbox_webview.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';

class ScanLinkPage extends StatefulWidget {
  final String? initialUrl;

  const ScanLinkPage({super.key, this.initialUrl});

  @override
  State<ScanLinkPage> createState() => _ScanLinkPageState();
}

class _ScanLinkPageState extends State<ScanLinkPage> {
  final _urlController = TextEditingController();
  String? result;
  bool isSafe = true;
  StreamSubscription<Uri>? _sub;
  final AppLinks _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) {
      _urlController.text = widget.initialUrl!;
      scanLink();
    } else {
      listenToIncomingLinks();
    }
  }

  Uri? lastUri;

  Future<void> handleInitialLink() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null && mounted && uri != lastUri) {
        lastUri = uri;
        _urlController.text = uri.toString();
        scanLink();
      }
    } catch (e) {
      debugPrint("Failed to get initial URI: $e");
    }
  }

  void listenToIncomingLinks() {
    _sub = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        if (uri != lastUri && mounted) {
          lastUri = uri;
          _urlController.text = uri.toString();
          scanLink();
        }
      },
      onError: (err) {
        debugPrint("Error receiving link: $err");
      },
    );
  }

  Future<void> openInChrome(String url) async {
    final uri = Uri.parse(url);
    const chromePackage = 'com.android.chrome';

    final androidIntent = AndroidIntent(
      action: 'action_view',
      data: uri.toString(),
      package: chromePackage,
    );

    try {
      await androidIntent.launch();
    } catch (e) {
      debugPrint("Chrome not found, falling back...");
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String? lastScannedUrl;

  void scanLink() async {
    String url = _urlController.text.trim();

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    if (url.isEmpty || url == lastScannedUrl) return;
    lastScannedUrl = url;

    setState(() {
      result = "⏳ Scanning...";
    });

    try {
      final isUnsafe = await UrlCheckerService.checkWithGoogleSafeBrowsing(url);

      if (isUnsafe) {
        setState(() {
          result = "⚠️ Unsafe Link Detected! Opening in sandbox...";
          isSafe = false;
        });

        await Future.delayed(const Duration(seconds: 1));

        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SandboxWebViewPage(url: url)),
        );
      } else {
        setState(() {
          result = "✅ Link Looks Safe. Opening in Chrome...";
          isSafe = true;
        });

        await Future.delayed(const Duration(seconds: 1));
        await openInChrome(url);
      }
    } catch (e) {
      setState(() {
        result = "❌ Error checking URL. Try again.";
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan Link")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: "Enter URL",
                prefixIcon: Icon(Icons.link),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: scanLink,
              icon: const Icon(Icons.shield),
              label: const Text("Scan now"),
            ),
            const SizedBox(height: 20),
            if (result != null)
              Text(
                result!,
                style: TextStyle(
                  color: isSafe ? Colors.green : Colors.red,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
