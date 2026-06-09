import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_ai/flutter_local_ai.dart';

void main() {
  runApp(const MyApp());
}

/// Which set of system instructions the shared on-device session currently
/// holds. The text tab and the genUI tab need different instructions, and the
/// native session is a singleton, so we re-initialize when switching modes.
enum _SessionMode { none, text, genui }

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

  // Tracks which instructions the shared native session currently holds.
  _SessionMode _sessionMode = _SessionMode.none;
  LocalAiBackend _backend = LocalAiBackend.unsupported;

  // --- Generative UI tab state ---
  final _goalController = TextEditingController();
  final _principlesController = TextEditingController();
  LocalAiUiGenerator? _uiGenerator;
  bool _genUiLoading = false;
  GenUiModuleSpec? _module;
  String _genUiError = '';

  static const _genUiExamples = <String>[
    'Save \$500 for a weekend trip',
    'Plan my dentist appointment',
    'Build a daily reading habit',
    'Track my monthly budget',
  ];

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

      // Detect the backend so the genUI tab can label it (best-effort).
      try {
        final info = await _aiEngine.getPlatformInfo();
        if (mounted) setState(() => _backend = info.backend);
      } catch (_) {/* keep unsupported */}

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
        if (success) _sessionMode = _SessionMode.text;
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

  /// Make sure the shared native session is initialized with the plain-assistant
  /// instructions before generating text — the genUI tab may have swapped in the
  /// schema instructions.
  Future<bool> _ensureTextSession() async {
    if (_sessionMode == _SessionMode.text && _isInitialized) return true;
    final ok = await _aiEngine.initialize(
      instructions: _instructionsController.text.isEmpty
          ? null
          : _instructionsController.text,
    );
    if (ok) {
      _sessionMode = _SessionMode.text;
      // Re-register tools: re-initializing the session drops them.
      if ((Platform.isIOS || Platform.isMacOS) && _toolsEnabled) {
        await _aiEngine.registerTools(_buildSampleTools());
      }
    }
    setState(() => _isInitialized = ok);
    return ok;
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
      // The genUI tab shares this session; restore the assistant instructions.
      if (!await _ensureTextSession()) {
        setState(() {
          _isLoading = false;
          _response = 'Error: failed to initialize the model session.';
        });
        return;
      }

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

  /// Generative UI: turn the user's goal into a [GenUiModuleSpec] with the
  /// on-device model, then render the typed blocks below.
  Future<void> _generateUi() async {
    final goal = _goalController.text.trim();
    if (goal.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Describe what you want to build')),
      );
      return;
    }

    setState(() {
      _genUiLoading = true;
      _genUiError = '';
    });

    // Use a fresh generator whenever the shared session isn't already in genUI
    // mode, so its schema instructions get (re)applied to the native session.
    if (_sessionMode != _SessionMode.genui || _uiGenerator == null) {
      _uiGenerator = LocalAiUiGenerator(_aiEngine);
    }
    final generator = _uiGenerator!;

    final principles = _principlesController.text.trim();
    final spec = await generator.generateModule(
      goal,
      principles: principles.isEmpty ? null : principles,
    );

    setState(() {
      _genUiLoading = false;
      _backend = generator.backend;
      _isAvailable = generator.available ?? _isAvailable;
      if (generator.available == true) {
        _sessionMode = _SessionMode.genui;
        _isInitialized = true;
      }
      if (spec == null) {
        _module = null;
        _genUiError = generator.lastError ?? 'Could not generate a module.';
      } else {
        _module = spec;
        _genUiError = '';
      }
    });
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
    _goalController.dispose();
    _principlesController.dispose();
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

  String _backendLabel(LocalAiBackend backend) {
    switch (backend) {
      case LocalAiBackend.appleFoundationModels:
        return 'Apple Foundation Models';
      case LocalAiBackend.androidMlKitGenAi:
        return 'Android ML Kit GenAI (Gemini Nano)';
      case LocalAiBackend.windowsAiFoundry:
        return 'Windows AI Foundry';
      case LocalAiBackend.windowsAiFoundryUnconfigured:
        return 'Windows AI (unconfigured)';
      case LocalAiBackend.unsupported:
      default:
        return 'Unsupported';
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: Text(widget.title),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.auto_awesome), text: 'Generative UI'),
              Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Text'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildGenUiTab(context),
            _buildTextTab(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTextTab(BuildContext context) {
    final isDarwin = !kIsWeb && (Platform.isIOS || Platform.isMacOS);

    return SingleChildScrollView(
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
            Card(
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
                    Text(
                      _response,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGenUiTab(BuildContext context) {
    final canGenerate = _isAvailable && !_genUiLoading;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Intro / status card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: Colors.deepPurple),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Describe a goal and the on-device model designs a '
                          'small UI module for it.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        _isAvailable ? Icons.check_circle : Icons.error,
                        size: 18,
                        color: _isAvailable ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _isAvailable
                              ? 'Backend: ${_backendLabel(_backend)}'
                              : 'Local AI is not available',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Goal field
          TextField(
            controller: _goalController,
            decoration: const InputDecoration(
              labelText: 'What do you want to build?',
              border: OutlineInputBorder(),
              hintText: 'e.g. Save \$500 for a weekend trip',
            ),
            maxLines: 2,
            enabled: _isAvailable,
          ),
          const SizedBox(height: 8),

          // Example chips
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final example in _genUiExamples)
                ActionChip(
                  label: Text(example),
                  onPressed: _isAvailable
                      ? () => setState(() {
                            _goalController.text = example;
                            _goalController.selection =
                                TextSelection.fromPosition(
                              TextPosition(offset: example.length),
                            );
                          })
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Optional guiding principles
          ExpansionTile(
            title: const Text('Guiding principles (Optional)'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              TextField(
                controller: _principlesController,
                decoration: const InputDecoration(
                  labelText: 'Principles the module should respect',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Keep it simple and low-pressure',
                ),
                maxLines: 2,
                enabled: _isAvailable,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Generate button
          ElevatedButton.icon(
            onPressed: canGenerate ? _generateUi : null,
            icon: _genUiLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(_genUiLoading ? 'Designing...' : 'Generate UI'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),

          if (_genUiError.isNotEmpty)
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _genUiError,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_module != null) _buildModule(context, _module!),
        ],
      ),
    );
  }

  // --- Generated module rendering ---

  Widget _buildModule(BuildContext context, GenUiModuleSpec module) {
    final tone = _toneColor(module.tone);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: tone.withValues(alpha: 0.2),
                  child: Icon(_lucideIcon(module.icon), color: tone),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        module.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (module.blurb.isNotEmpty)
                        Text(
                          module.blurb,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey[700]),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final block in module.blocks) ...[
              _buildBlock(context, block, tone),
              const SizedBox(height: 12),
            ],
            const Divider(),
            ExpansionTile(
              title: const Text('View module JSON'),
              tilePadding: EdgeInsets.zero,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ')
                        .convert(module.toModuleJson()),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlock(BuildContext context, Map<String, dynamic> b, Color tone) {
    final type = (b['type'] ?? '').toString();
    Widget content;
    switch (type) {
      case 'amount':
        content = _amountBlock(context, b);
        break;
      case 'progress':
        content = _progressBlock(context, b, tone);
        break;
      case 'checklist':
        content = _checklistBlock(context, b, tone);
        break;
      case 'week':
        content = _weekBlock(context, b, tone);
        break;
      case 'stat':
        content = _statBlock(context, b);
        break;
      case 'list':
        content = _listBlock(context, b);
        break;
      case 'lessons':
        content = _lessonsBlock(context, b, tone);
        break;
      case 'reminder':
        content = _reminderBlock(context, b, tone);
        break;
      case 'calc':
        content = _calcBlock(context, b);
        break;
      case 'note':
        content = Text(
          (b['text'] ?? '').toString(),
          style: Theme.of(context).textTheme.bodyMedium,
        );
        break;
      default:
        content = _genericBlock(context, b);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: tone, width: 3)),
      ),
      child: content,
    );
  }

  Widget _blockLabel(BuildContext context, String label) => Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: Colors.grey[700]),
      );

  Widget _amountBlock(BuildContext context, Map<String, dynamic> b) {
    final prefix = (b['prefix'] ?? '').toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _blockLabel(context, (b['label'] ?? 'Amount').toString()),
        const SizedBox(height: 4),
        Text(
          '$prefix${b['value'] ?? 0}',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _progressBlock(
      BuildContext context, Map<String, dynamic> b, Color tone) {
    final prefix = (b['prefix'] ?? '').toString();
    final value = _toDouble(b['value']);
    final target = _toDouble(b['target']);
    final ratio = target > 0 ? (value / target).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _blockLabel(context, (b['label'] ?? 'Progress').toString()),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 10,
            color: tone,
            backgroundColor: tone.withValues(alpha: 0.15),
          ),
        ),
        const SizedBox(height: 6),
        Text('$prefix${b['value'] ?? 0} of $prefix${b['target'] ?? 0}'),
      ],
    );
  }

  Widget _checklistBlock(
      BuildContext context, Map<String, dynamic> b, Color tone) {
    final items = (b['items'] as List?) ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _blockLabel(context, (b['label'] ?? 'Checklist').toString()),
        const SizedBox(height: 4),
        for (final raw in items)
          if (raw is Map)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    (raw['done'] == true)
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 20,
                    color: tone,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((raw['label'] ?? '').toString()),
                        if ((raw['meta'] ?? '').toString().isNotEmpty)
                          Text(
                            raw['meta'].toString(),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _weekBlock(BuildContext context, Map<String, dynamic> b, Color tone) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final days = (b['days'] as List?) ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _blockLabel(context, (b['label'] ?? 'This week').toString()),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < labels.length; i++)
              CircleAvatar(
                radius: 16,
                backgroundColor: (i < days.length && days[i] == true)
                    ? tone
                    : tone.withValues(alpha: 0.15),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    color: (i < days.length && days[i] == true)
                        ? Colors.white
                        : Colors.grey[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _statBlock(BuildContext context, Map<String, dynamic> b) {
    final value = b['value']?.toString() ??
        (b['dynamic'] != null ? '(${b['dynamic']})' : '—');
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _blockLabel(context, (b['label'] ?? 'Stat').toString()),
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _listBlock(BuildContext context, Map<String, dynamic> b) {
    final prefix = (b['prefix'] ?? '').toString();
    final rows = (b['rows'] as List?) ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _blockLabel(context, (b['label'] ?? 'List').toString()),
        const SizedBox(height: 4),
        for (final raw in rows)
          if (raw is Map)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text((raw['name'] ?? '').toString())),
                  Text('$prefix${raw['amount'] ?? 0}'),
                ],
              ),
            ),
      ],
    );
  }

  Widget _lessonsBlock(
      BuildContext context, Map<String, dynamic> b, Color tone) {
    final items = (b['items'] as List?) ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _blockLabel(context, (b['label'] ?? 'Lessons').toString()),
        const SizedBox(height: 4),
        for (final raw in items)
          if (raw is Map)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    (raw['read'] == true)
                        ? Icons.task_alt
                        : Icons.menu_book_outlined,
                    size: 18,
                    color: tone,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text((raw['title'] ?? '').toString())),
                  if (raw['mins'] != null)
                    Text(
                      '${raw['mins']} min',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _reminderBlock(
      BuildContext context, Map<String, dynamic> b, Color tone) {
    final parts = <String>[
      if ((b['date'] ?? '').toString().isNotEmpty) b['date'].toString(),
      if ((b['time'] ?? '').toString().isNotEmpty) b['time'].toString(),
      if ((b['location'] ?? '').toString().isNotEmpty) b['location'].toString(),
    ];
    return Row(
      children: [
        Icon(Icons.notifications_active_outlined, color: tone),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (b['title'] ?? 'Reminder').toString(),
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (parts.isNotEmpty)
                Text(
                  parts.join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _calcBlock(BuildContext context, Map<String, dynamic> b) {
    final inputs = (b['inputs'] as List?) ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.calculate_outlined, size: 18),
            const SizedBox(width: 6),
            _blockLabel(context, (b['label'] ?? 'Calculator').toString()),
          ],
        ),
        const SizedBox(height: 4),
        for (final raw in inputs)
          if (raw is Map)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text((raw['label'] ?? '').toString())),
                  Text('${raw['prefix'] ?? ''}${raw['value'] ?? 0}'),
                ],
              ),
            ),
        if ((b['resultLabel'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '→ ${b['resultLabel']}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }

  Widget _genericBlock(BuildContext context, Map<String, dynamic> b) {
    final label =
        (b['label'] ?? b['title'] ?? b['text'] ?? b['type'] ?? 'Block')
            .toString();
    return Row(
      children: [
        const Icon(Icons.widgets_outlined, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
      ],
    );
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  Color _toneColor(String tone) {
    switch (tone) {
      case 'apricot':
        return const Color(0xFFE8954F);
      case 'sky':
        return const Color(0xFF4F9BE8);
      case 'lilac':
        return const Color(0xFF9C7BD6);
      case 'fern':
      default:
        return const Color(0xFF5BA871);
    }
  }

  IconData _lucideIcon(String name) {
    switch (name) {
      case 'piggy-bank':
      case 'wallet':
        return Icons.savings;
      case 'dollar-sign':
      case 'coins':
        return Icons.attach_money;
      case 'calendar':
      case 'calendar-days':
        return Icons.calendar_today;
      case 'bell':
        return Icons.notifications;
      case 'check':
      case 'check-circle':
        return Icons.check_circle;
      case 'list':
      case 'list-checks':
        return Icons.checklist;
      case 'book':
      case 'book-open':
      case 'graduation-cap':
        return Icons.menu_book;
      case 'target':
      case 'flag':
        return Icons.flag;
      case 'trending-up':
        return Icons.trending_up;
      case 'heart':
        return Icons.favorite;
      case 'sparkles':
      default:
        return Icons.auto_awesome;
    }
  }
}
