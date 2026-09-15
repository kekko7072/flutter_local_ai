import 'package:flutter/foundation.dart';

import 'local_ai_host.dart';
// Web is the default arm and native overrides it, mirroring how the rest of
// the Flutter on-device-AI ecosystem splits: `dart.library.ffi` is true on
// Android/iOS/macOS/Windows and false under dart2js/dart2wasm.
import 'web/local_ai_host_web.dart'
    if (dart.library.ffi) 'local_ai_host_native.dart'
    as impl;

LocalAiHost? _host;

/// The platform host for this build — pigeon-backed natively, Chrome Prompt
/// API on the web. Created once and shared, so every session and the
/// availability facade drive the same channel and event stream.
LocalAiHost get localAiHost => _host ??= impl.createLocalAiHost();

/// Swaps in a fake host. Tests only — pass null to restore the real one.
@visibleForTesting
set debugLocalAiHost(LocalAiHost? host) => _host = host;
