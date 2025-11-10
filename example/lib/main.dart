import 'package:flutter/material.dart';
import 'package:flutter_local_ai/flutter_local_ai.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Local AI Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Local AI Example'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _aiEngine = FlutterLocalAi();
  final _promptController = TextEditingController();
  final _instructionsController = TextEditingController(
    text: 'You are a helpful assistant. Provide concise answers.',
  );
  String _response = '';
  bool _isLoading = false;
  bool _isAvailable = false;
  bool _isInitialized = false;
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    final available = await _aiEngine.isAvailable();
    setState(() {
      _isAvailable = available;
    });

    // Auto-initialize if available
    if (available && !_isInitialized) {
      _initialize();
    }
  }

  Future<void> _initialize() async {
    if (_isInitializing || _isInitialized) return;

    setState(() {
      _isInitializing = true;
    });

    try {
      final success = await _aiEngine.initialize(
        instructions: _instructionsController.text.isEmpty
            ? null
            : _instructionsController.text,
      );

      setState(() {
        _isInitialized = success;
        _isInitializing = false;
      });

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI model initialized successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to initialize AI model'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isInitialized = false;
        _isInitializing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error initializing: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _generateText() async {
    if (_promptController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a prompt')),
      );
      return;
    }

    if (!_isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please initialize the AI model first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _response = '';
    });

    try {
      final response = await _aiEngine.generateText(
        prompt: _promptController.text,
        config: const GenerationConfig(maxTokens: 200),
      );

      setState(() {
        _response = response.text;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _response = 'Error: $e';
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Generation error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isAvailable ? Icons.check_circle : Icons.error,
                          color: _isAvailable ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isAvailable
                              ? 'Local AI is available'
                              : 'Local AI is not available',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    if (_isAvailable) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            _isInitialized ? Icons.check_circle : Icons.pending,
                            color:
                                _isInitialized ? Colors.green : Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isInitialized
                                ? 'Model initialized'
                                : _isInitializing
                                    ? 'Initializing...'
                                    : 'Model not initialized',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Instructions TextField (expandable)
            ExpansionTile(
              title: const Text('Custom Instructions (Optional)'),
              initiallyExpanded: true,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _instructionsController,
                    decoration: const InputDecoration(
                      labelText: 'Instructions for the AI',
                      border: OutlineInputBorder(),
                      hintText: 'You are a helpful assistant...',
                      helperText:
                          'These instructions will be used when initializing the model',
                    ),
                    maxLines: 3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Initialize Button
            if (_isAvailable && !_isInitialized)
              ElevatedButton.icon(
                onPressed: _isInitializing ? null : _initialize,
                icon: _isInitializing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.settings),
                label: Text(
                    _isInitializing ? 'Initializing...' : 'Initialize Model'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            if (_isAvailable && !_isInitialized) const SizedBox(height: 16),

            // Prompt TextField
            TextField(
              controller: _promptController,
              decoration: const InputDecoration(
                labelText: 'Enter your prompt',
                border: OutlineInputBorder(),
                hintText: 'Write a short story about a robot...',
              ),
              maxLines: 3,
              enabled: _isInitialized,
            ),
            const SizedBox(height: 16),

            // Generate Button
            ElevatedButton(
              onPressed: (_isLoading || !_isInitialized) ? null : _generateText,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Generate Text'),
            ),
            const SizedBox(height: 16),

            // Response Card
            if (_response.isNotEmpty)
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Response:',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Text(
                              _response,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
