library;

export 'src/flutter_local_ai.dart';
export 'src/models/ai_response.dart';
export 'src/models/generation_config.dart';
export 'src/models/model_status.dart';
export 'src/models/platform_info.dart';
export 'src/models/tool.dart';

// Session API: the multi-session, buffer-then-generate surface the
// flutter_gemma engine (package:flutter_local_ai/gemma.dart) is built on.
// Usable directly too — it is the fuller of the two APIs, and the only one
// with images, concurrent sessions, cancellation and exact token counts.
export 'src/session/local_ai.dart';
export 'src/session/local_ai_host.dart'
    show
        LocalAiAvailability,
        LocalAiBackendCapabilities,
        LocalAiBackendKind,
        LocalAiGenerationOverrides,
        LocalAiHost,
        LocalAiHostEvent,
        LocalAiTokenEvent,
        LocalAiErrorEvent,
        LocalAiDownloadProgressEvent,
        LocalAiTokenizerUnavailable,
        LocalAiUnavailableException,
        LocalAiUnsupportedException;
export 'src/session/local_ai_model.dart';
// `debugLocalAiHost` lets tests (and the bridge package's tests) swap in a
// fake host without reaching into src/.
export 'src/session/local_ai_runtime.dart';
export 'src/session/local_ai_session.dart';

// genUI integration: turn a user goal into a genui-renderable module spec.
export 'src/genui/genui_module_spec.dart';
export 'src/genui/local_ai_ui_generator.dart';
