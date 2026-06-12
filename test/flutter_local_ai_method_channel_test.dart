import 'package:flutter/services.dart';
import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_local_ai/src/flutter_local_ai_method_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_local_ai');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('MethodChannelFlutterLocalAi.downloadModel', () {
    test('a failed method call surfaces as a failed status on the stream',
        () async {
      // Older platform code (or an unsupported platform) can fail the
      // downloadModel call without ever emitting an onDownloadStatus event.
      // The stream must still end the download — a silent error would leave
      // watchers spinning forever.
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'downloadModel') {
          throw PlatformException(
              code: 'DOWNLOAD_ERROR', message: 'AICore says no');
        }
        return null;
      });

      final platform = MethodChannelFlutterLocalAi();
      final status = await platform.downloadModel().first;

      expect(status.type, ModelDownloadStatusType.failed);
      expect(status.errorMessage, contains('AICore says no'));
    });

    test('platform onDownloadStatus events are forwarded to the stream',
        () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);

      final platform = MethodChannelFlutterLocalAi();
      final first = platform.downloadModel().first;

      // Simulate the native side reporting progress.
      await messenger.handlePlatformMessage(
        'flutter_local_ai',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onDownloadStatus', {
            'status': 'progress',
            'totalBytesDownloaded': 1234,
          }),
        ),
        (_) {},
      );

      final status = await first;
      expect(status.type, ModelDownloadStatusType.progress);
      expect(status.totalBytesDownloaded, 1234);
    });
  });
}
