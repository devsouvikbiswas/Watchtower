import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SandboxWebViewPage extends StatefulWidget {
  final String url;

  const SandboxWebViewPage({super.key, required this.url});

  @override
  State<SandboxWebViewPage> createState() => _SandboxWebViewPageState();
}

class _SandboxWebViewPageState extends State<SandboxWebViewPage> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final originalUrl = widget.url;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled) // Disable JS for safety
      ..setBackgroundColor(const Color(0xFF1E1E2C))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            // Block redirects or any navigation to a different URL
            if (request.url != originalUrl) {
              debugPrint("Blocked redirect to: ${request.url}");
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (_) {
            setState(() {
              _isLoading = false;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sandbox View")),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
