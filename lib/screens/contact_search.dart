import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for FilteringTextInputFormatter
import '../services/wb_police_scraper_service.dart';

class ContactSearchScreen extends StatefulWidget {
  const ContactSearchScreen({super.key});

  @override
  State<ContactSearchScreen> createState() => _ContactSearchScreenState();
}

class _ContactSearchScreenState extends State<ContactSearchScreen> {
  // Instance of the scraping service
  final WBPoliceScraperService _scraper = WBPoliceScraperService();
  // Controller for the search input field
  final TextEditingController _searchController = TextEditingController();
  // Focus node for the search input field
  final FocusNode _searchFocusNode = FocusNode();

  // State variables for UI
  bool _isLoading = false; // Indicates if a search operation is in progress
  bool _isInitializing =
      false; // Indicates if the database is being initialized
  String _searchResult = ''; // Message to display search outcome
  Map<String, dynamic>?
  _foundContact; // Stores the found contact details, now dynamic

  @override
  void initState() {
    super.initState();
    _checkAndInitializeDatabaseOnStartup(); // New method for file-based check
  }

  /// Checks if the database file exists and is not empty on app startup.
  /// If not, it triggers the database initialization (scraping).
  Future<void> _checkAndInitializeDatabaseOnStartup() async {
    setState(() {
      _isInitializing = true; // Indicate loading for initial check
      _searchResult = 'Checking database...'; // Set initial status message
    });

    try {
      final bool dbExists = await _scraper
          .contactsExistAndNotEmpty(); // Use the new method

      if (!dbExists) {
        // File not found, or empty
        print('Contact database file not found or is empty. Initializing...');
        await _initializeDatabase(initialRun: true); // Run full initialization
      } else {
        print(
          'Contact database file found and contains data. Skipping initial scraping.',
        );
        setState(() {
          _searchResult = 'Database loaded, ready to search!';
        });
      }
    } catch (e) {
      print('Error during initial database check: $e');
      setState(() {
        _searchResult = 'Error loading database: $e';
      });
    } finally {
      setState(() => _isInitializing = false); // Reset loading state
    }
  }

  /// Initializes the contact database by fetching and storing contacts.
  /// Displays a snackbar if initialization fails.
  /// [initialRun] indicates if this is the automatic startup initialization.
  Future<void> _initializeDatabase({bool initialRun = false}) async {
    // Combined initial setState to prevent flashing
    setState(() {
      _isInitializing = true;
      _searchResult = initialRun
          ? 'Initializing contact database... Please wait, this may take a moment.'
          : 'Refreshing database... Please wait.';
      _foundContact = null; // Clear any previously found contact
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          initialRun
              ? 'Starting initial database setup...'
              : 'Starting database refresh...',
        ),
      ),
    );
    try {
      await _scraper.fetchAndStoreContacts();
      // Update message after successful completion
      setState(() {
        _searchResult = initialRun
            ? 'Database initialized successfully!'
            : 'Database refreshed successfully!';
        _foundContact =
            null; // Still clear found contact as the data may have changed
        _searchController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            initialRun
                ? 'Database setup complete!'
                : 'Database refresh complete!',
          ),
        ),
      );
    } catch (e) {
      // Show error message on failure
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to initialize database: $e')),
      );
      setState(() {
        _searchResult = 'Initialization/Refresh failed: $e';
      });
    } finally {
      setState(() => _isInitializing = false); // Reset loading state
    }
  }

  /// Performs a search for a contact based on the entered phone number.
  /// Updates UI with search results.
  Future<void> _searchContact() async {
    final phoneNumber = _searchController.text.trim();
    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a phone number to search.')),
      );
      return;
    }

    setState(() {
      _isLoading = true; // Set loading state for search
      _searchResult = ''; // Clear previous results
      _foundContact = null;
    });

    try {
      final contact = await _scraper.searchContact(phoneNumber);

      setState(() {
        _foundContact = contact;
        _searchResult =
            (contact !=
                null) // Now checking for null, as searchContact returns null if not found
            ? 'Match found!'
            : 'No match found in database';
      });
    } catch (e) {
      setState(() {
        _searchResult = 'Search error: $e'; // Display search error
      });
    } finally {
      setState(() => _isLoading = false); // Reset loading state
      _searchFocusNode.unfocus(); // Dismiss keyboard
    }
  }

  /// Flags the currently entered phone number as a scammer.
  /// If the number exists, it updates its scammer status. If new, it adds it.
  Future<void> _flagScammerContact() async {
    final phoneNumber = _searchController.text.trim();
    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a phone number to flag as scammer.'),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _searchResult = '';
    });

    try {
      // Create a contact map for the scammer number
      // Prioritize existing details if found, otherwise just phone and scammer flag
      Map<String, dynamic> scammerData = {
        'phone': phoneNumber,
        'isScammer': true, // Mark as scammer
        'name':
            _foundContact?['name'] ??
            'Flagged Number', // Use existing name or default
        'designation':
            _foundContact?['designation'] ??
            'Scammer', // Use existing designation or default
      };

      await _scraper.addOrUpdateContact(scammerData);

      setState(() {
        _searchResult = 'Number $phoneNumber flagged as scammer successfully!';
        _foundContact = scammerData; // Update UI to reflect the flagged status
        _searchController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Number $phoneNumber flagged as scammer!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to flag number as scammer: $e')),
      );
      setState(() {
        _searchResult = 'Error flagging number: $e';
      });
    } finally {
      setState(() => _isLoading = false);
      _searchFocusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Number Checker'), // Updated title
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading || _isInitializing
                ? null
                : () => _initializeDatabase(
                    initialRun: false,
                  ), // Always allow manual refresh
            tooltip: 'Refresh Database',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (_isInitializing) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
              // Display current initialization/refresh message
              Text(
                _searchResult,
                style: const TextStyle(
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
            ],
            TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                labelText: 'Enter phone number',
                hintText: 'e.g. 9876543210',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _isLoading || _isInitializing
                      ? null
                      : _searchContact,
                ),
              ),
              keyboardType:
                  TextInputType.phone, // Ensures numerical keyboard on mobile
              inputFormatters: [
                // Restricts input to digits only
                FilteringTextInputFormatter.digitsOnly,
              ],
              onSubmitted: (_) =>
                  _isLoading || _isInitializing ? null : _searchContact(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading || _isInitializing
                    ? null
                    : _searchContact,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Search Contact'),
              ),
            ),
            const SizedBox(height: 10), // Added spacing for the new button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.flag_outlined), // Flag icon
                label: const Text('Flag as Scammer'),
                onPressed:
                    _isLoading ||
                        _isInitializing ||
                        _searchController.text.trim().isEmpty
                    ? null // Disable if busy or no number entered
                    : _flagScammerContact,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      Colors.red.shade700, // Red color for scammer flag
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Only show search result text if not currently initializing
            if (_searchResult.isNotEmpty && !_isInitializing) ...[
              Text(
                _searchResult,
                style: TextStyle(
                  fontSize: 18,
                  // Color based on scammer status or search result
                  color:
                      (_foundContact != null &&
                          (_foundContact!['isScammer'] == true))
                      ? Colors
                            .red
                            .shade700 // Red for scammer
                      : (_foundContact != null)
                      ? Colors.green
                      : Colors.orange, // Green for found, orange for not found
                  fontWeight:
                      (_foundContact != null &&
                          (_foundContact!['isScammer'] == true))
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              if (_foundContact != null) ...[
                // Check only for null here
                const SizedBox(height: 20),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Name: ${_foundContact!['name'] ?? 'N/A'}', // Added null check with default
                          style: const TextStyle(fontSize: 16),
                        ),
                        Text(
                          'Designation: ${_foundContact!['designation'] ?? 'N/A'}', // Added null check with default
                          style: const TextStyle(fontSize: 16),
                        ),
                        Text(
                          'Phone: ${_foundContact!['phone'] ?? 'N/A'}', // Added null check with default
                          style: const TextStyle(fontSize: 16),
                        ),
                        if (_foundContact!['isScammer'] ==
                            true) // Display scammer status if true
                          Text(
                            'Status: SCAMMER',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }
}
