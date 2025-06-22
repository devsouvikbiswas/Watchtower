import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/contact_search.dart';
import 'package:app_links/app_links.dart';
import 'screens/scan_link.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Uri? initialUri;
  bool isReady = false;

  @override
  void initState() {
    super.initState();
    _checkInitialLink();
  }

  Future<void> _checkInitialLink() async {
    final appLinks = AppLinks();
    try {
      final uri = await appLinks.getInitialLink();
      setState(() {
        initialUri = uri;
        isReady = true;
      });
    } catch (e) {
      setState(() {
        isReady = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isReady) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      title: 'Watch Tower',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF1E1E2C),
        cardColor: const Color(0xFF2E2E3E),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: const MyHomePage(title: 'Watch Tower'),
      routes: {
        '/scan-link': (context) =>
            const ScanLinkPage(), // Assuming ScanLinkScreen is the widget for /scan-link
        '/contact-search': (context) =>
            const ContactSearchScreen(), // Assuming ContactSearchScreen is the widget for /contact-search
        // Add other routes as needed
      },
    );
  }
}

class MyHomePage extends StatelessWidget {
  final String title;
  const MyHomePage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final features = [
      {'icon': Icons.link, 'label': 'Scan Link'},
      {'icon': Icons.call, 'label': 'Call Monitor'},
      {'icon': Icons.phone, 'label': 'Number Checker'},
      {'icon': Icons.history, 'label': 'Logs'},
    ];

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              "Welcome, stay safe online!",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              padding: const EdgeInsets.all(12),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: features
                  .map(
                    (f) => FeatureCard(
                      icon: f['icon'] as IconData,
                      label: f['label'] as String,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class FeatureCard extends StatelessWidget {
  final IconData icon;
  final String label;

  const FeatureCard({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (label == 'Scan Link') {
          Navigator.pushNamed(context, '/scan-link');
        } else if (label == 'Number Checker') {
          Navigator.pushNamed(context, '/contact-search');
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Tapped "$label"')));
        }
      },
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: Colors.deepPurpleAccent),
              const SizedBox(height: 10),
              Text(label, style: const TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}
