import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
  String _errorMessage = '';
  bool _isLoading = false;
  bool _isAvailable = false;
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _toolsRegistered = false;
  bool _toolsEnabled = false;
  ModelFeatureStatus _modelStatus = ModelFeatureStatus.unknown;
  bool _isDownloading = false;
  int? _downloadedBytes;
  String _downloadError = '';
  StreamSubscription<ModelDownloadStatus>? _downloadSub;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    try {
      final available = await _aiEngine.isAvailable();
      setState(() {
        _isAvailable = available;
        _errorMessage = ''; // Clear error on success
      });

      if (Platform.isAndroid) {
        await _refreshModelStatus();
      }

      // Auto-initialize if available
      if (available && !_isInitialized) {
        _initialize();
      }
    } catch (e) {
      final errorStr = e.toString();
      setState(() {
        _isAvailable = false;
        _errorMessage = errorStr;
      });

      // Check if it's an AICore error (error code -101) - Android only
      if (errorStr.contains('-101') || errorStr.contains('AICore')) {
        _showAICoreErrorDialog();
      } else if (errorStr.contains('Windows AI') ||
          errorStr.contains('cppwinrt')) {
        // Windows AI headers not available
        if (mounted) {
          _showWindowsAIErrorDialog();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error checking availability: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _refreshModelStatus() async {
    try {
      final status = await _aiEngine.getModelStatus();
      setState(() {
        _modelStatus = status;
        _downloadError = '';
      });
    } catch (e) {
      final errorStr = e.toString();
      setState(() {
        _downloadError = errorStr;
        _modelStatus = ModelFeatureStatus.unknown;
      });

      if (errorStr.contains('-101') || errorStr.contains('AICore')) {
        _showAICoreErrorDialog();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking model status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _downloadModel() {
    if (!Platform.isAndroid || _isDownloading) return;

    setState(() {
      _isDownloading = true;
      _downloadedBytes = null;
      _downloadError = '';
    });

    _downloadSub?.cancel();
    _downloadSub = _aiEngine.downloadModel().listen(
      (status) async {
        switch (status.type) {
          case ModelDownloadStatusType.started:
            setState(() {
              _isDownloading = true;
              _downloadError = '';
            });
            break;
          case ModelDownloadStatusType.progress:
            setState(() {
              _downloadedBytes = status.totalBytesDownloaded;
            });
            break;
          case ModelDownloadStatusType.completed:
            setState(() {
              _isDownloading = false;
            });
            await _refreshModelStatus();
            await _checkAvailability();
            break;
          case ModelDownloadStatusType.failed:
            setState(() {
              _isDownloading = false;
              _downloadError = status.errorMessage ?? 'Download failed';
            });
            break;
          case ModelDownloadStatusType.unknown:
            setState(() {
              _downloadError = 'Unknown download status';
            });
            break;
        }
      },
      onError: (e) {
        setState(() {
          _isDownloading = false;
          _downloadError = e.toString();
        });
      },
      onDone: () {
        setState(() {
          _isDownloading = false;
        });
      },
    );
  }

  Future<void> _configureTools(bool enable) async {
    if (!Platform.isIOS && !Platform.isMacOS) return;
    try {
      final tools = enable ? _buildSampleTools() : <LocalAiTool>[];
      await _aiEngine.registerTools(tools);
      setState(() {
        _toolsRegistered = enable;
        _toolsEnabled = enable;
      });
    } catch (e) {
      debugPrint('Failed to register tools: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${enable ? "enable" : "disable"} tools: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<LocalAiTool> _buildSampleTools() {
    return [
      LocalAiTool(
        name: 'searchBreadDatabase',
        description: 'Searches a local database for bread recipes.',
        parameters: const [
          ToolParameter(
              name: 'searchTerm',
              type: ToolArgumentType.string,
              description: 'Type of bread to search for',
            ),
            ToolParameter(
              name: 'limit',
              type: ToolArgumentType.integer,
              description: 'Number of recipes to return',
            ),
          ],
          onCall: (arguments) async {
            final term = arguments['searchTerm']?.toString() ?? '';
            final limit = (arguments['limit'] as num?)?.toInt() ?? 2;
            // Replace with your own data lookup
            return List.generate(
              limit,
              (index) => 'Recipe ${index + 1} for "$term"',
            );
          },
        ),
      LocalAiTool(
        name: 'quickMath',
        description: 'Performs a basic arithmetic operation on two numbers.',
        parameters: const [
          ToolParameter(
            name: 'a',
            type: ToolArgumentType.number,
            description: 'First number',
          ),
          ToolParameter(
            name: 'b',
            type: ToolArgumentType.number,
            description: 'Second number',
          ),
          ToolParameter(
            name: 'operation',
            type: ToolArgumentType.string,
            description: 'One of add, subtract, multiply, divide',
          ),
        ],
        onCall: (arguments) async {
          final a = (arguments['a'] as num?)?.toDouble() ?? 0;
          final b = (arguments['b'] as num?)?.toDouble() ?? 0;
          final op = (arguments['operation']?.toString() ?? '').toLowerCase();

          switch (op) {
            case 'add':
              return a + b;
            case 'subtract':
              return a - b;
            case 'multiply':
              return a * b;
            case 'divide':
              if (b == 0) {
                return 'Cannot divide by zero';
              }
              return a / b;
            default:
              return 'Unsupported operation "$op". Try add, subtract, multiply, or divide.';
          }
        },
      ),
    ];
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('AI model initialized successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to initialize AI model'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isInitialized = false;
        _isInitializing = false;
      });

      // Check if it's an AICore error (error code -101) - Android only
      if (e.toString().contains('-101') || e.toString().contains('AICore')) {
        _showAICoreErrorDialog();
      } else if (e.toString().contains('Windows AI') ||
          e.toString().contains('cppwinrt')) {
        // Windows AI headers not available
        if (mounted) {
          _showWindowsAIErrorDialog();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error initializing: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _generateText() async {
    if (_promptController.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a prompt')),
        );
      }
      return;
    }

    if (!_isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please initialize the AI model first'),
            backgroundColor: Colors.orange,
          ),
        );
      }
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

      // Check if it's an AICore error (error code -101) - Android only
      if (e.toString().contains('-101') || e.toString().contains('AICore')) {
        _showAICoreErrorDialog();
      } else if (e.toString().contains('Windows AI') ||
          e.toString().contains('cppwinrt')) {
        // Windows AI headers not available
        if (mounted) {
          _showWindowsAIErrorDialog();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Generation error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showAICoreErrorDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 8),
              Text('AICore Required'),
            ],
          ),
          content: const Text(
            'Google AICore is required for on-device AI but it\'s not installed or the version is too low.\n\n'
            'AICore is a system-level app that enables local AI features on your device, similar to Google Play Services.\n\n'
            'Would you like to install it from the Play Store?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  await _aiEngine.openAICorePlayStore();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Could not open Play Store: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.store),
              label: const Text('Open Play Store'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  void _showWindowsAIErrorDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.info, color: Colors.blue),
              SizedBox(width: 8),
              Text('Windows AI Setup Required'),
            ],
          ),
          content: const Text(
            'Windows AI headers are not available. To enable Windows AI support:\n\n'
            '1. Install the Windows AI SDK or obtain Microsoft.Windows.AI.winmd\n'
            '2. Generate C++/WinRT headers using cppwinrt.exe\n'
            '3. Add the generated headers path to CMakeLists.txt\n'
            '4. Uncomment the Windows AI include in flutter_local_ai_plugin.cpp\n\n'
            'See the README for detailed instructions.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    _promptController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes} B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  String _modelStatusLabel(ModelFeatureStatus status) {
    switch (status) {
      case ModelFeatureStatus.available:
        return 'Model downloaded';
      case ModelFeatureStatus.downloadable:
        return 'Model not downloaded';
      case ModelFeatureStatus.downloading:
        return 'Download in progress';
      case ModelFeatureStatus.unavailable:
        return 'Model unavailable';
      case ModelFeatureStatus.unknown:
      default:
        return 'Unknown status';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarwin = !kIsWeb && (Platform.isIOS || Platform.isMacOS);
    
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isAvailable
                                    ? 'Local AI is available'
                                    : 'Local AI is not available',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (!kIsWeb)
                                Text(
                                  Platform.isWindows
                                      ? 'Windows'
                                      : Platform.isAndroid
                                          ? 'Android'
                                          : Platform.isIOS
                                              ? 'iOS'
                                              : Platform.isMacOS
                                                  ? 'macOS'
                                                  : 'Unknown',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Colors.grey,
                                      ),
                                ),
                            ],
                          ),
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
                    ] else if (_errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage.contains('Windows AI') ||
                                _errorMessage.contains('cppwinrt')
                            ? 'Windows AI headers not configured'
                            : 'Error: ${_errorMessage.length > 100 ? "${_errorMessage.substring(0, 100)}..." : _errorMessage}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.orange,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (Platform.isAndroid)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _modelStatus == ModelFeatureStatus.available
                                ? Icons.check_circle
                                : _modelStatus ==
                                        ModelFeatureStatus.downloadable
                                    ? Icons.download
                                    : _modelStatus ==
                                            ModelFeatureStatus.downloading
                                        ? Icons.downloading
                                        : Icons.info,
                            color: _modelStatus == ModelFeatureStatus.available
                                ? Colors.green
                                : _modelStatus ==
                                        ModelFeatureStatus.downloadable
                                    ? Colors.orange
                                    : _modelStatus ==
                                            ModelFeatureStatus.downloading
                                        ? Colors.blue
                                        : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _modelStatusLabel(_modelStatus),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      if (_isDownloading || _modelStatus == ModelFeatureStatus.downloading) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _downloadedBytes != null
                                  ? 'Downloading: ${_formatBytes(_downloadedBytes!)}'
                                  : 'Downloading...',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                      if (_downloadError.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _downloadError,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.red),
                        ),
                      ],
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: (_modelStatus ==
                                    ModelFeatureStatus.downloadable &&
                                !_isDownloading)
                            ? _downloadModel
                            : null,
                        icon: const Icon(Icons.download),
                        label: const Text('Download Model'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (Platform.isAndroid) const SizedBox(height: 16),

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
            
            if (isDarwin) ...[
              Card(
                child: SwitchListTile(
                  title: const Text('Enable tool calls (iOS/macOS only)'),
                  subtitle: const Text(
                    'Expose sample tools: searchBreadDatabase and quickMath.',
                  ),
                  value: _toolsEnabled,
                  onChanged: (value) async {
                    await _configureTools(value);
                  },
                ),
              ),
              if (_toolsEnabled)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    'Try: "Use quickMath to add 4 and 9" or "Find 2 sourdough recipes with searchBreadDatabase".',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey[700]),
                  ),
                ),
            ],

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
