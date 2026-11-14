import 'package:flutter_local_ai/flutter_local_ai.dart';
import 'package:flutter_local_ai/src/pigeon/local_ai_api.g.dart' as wire;
import 'package:flutter_local_ai/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('execution policy', () {
    test('wire enum order is stable and append-only', () {
      expect(wire.LocalAiExecutionPolicy.onDeviceOnly.index, 0);
      expect(wire.LocalAiExecutionPolicy.cloudOnly.index, 1);
      expect(wire.LocalAiExecutionPolicy.preferOnDevice.index, 2);
      expect(wire.LocalAiExecutionPolicy.preferCloud.index, 3);
      expect(wire.LocalAiExecutionLocation.onDevice.index, 0);
      expect(wire.LocalAiExecutionLocation.privateCloudCompute.index, 1);
    });

    test('existing calls remain on-device only', () async {
      final host = FakeLocalAiHost();
      final model = await LocalAiModel.create(host: host);
      expect(model.executionPolicy, LocalAiExecutionPolicy.onDeviceOnly);
      expect(model.executionLocation, LocalAiExecutionLocation.onDevice);
      expect(host.modelExecutionPolicy, LocalAiExecutionPolicy.onDeviceOnly);
      await model.close();
      await host.dispose();
    });

    test(
      'preferOnDevice reports a PCC fallback on model and session',
      () async {
        final host = FakeLocalAiHost();
        host.policySelections[LocalAiExecutionPolicy.preferOnDevice] =
            const LocalAiModelSelection(
              executionLocation: LocalAiExecutionLocation.privateCloudCompute,
              provider: 'Apple Private Cloud Compute',
              fallbackUsed: true,
            );

        final model = await LocalAiModel.create(
          host: host,
          executionPolicy: LocalAiExecutionPolicy.preferOnDevice,
        );
        final session = await model.openSession();

        expect(
          model.executionLocation,
          LocalAiExecutionLocation.privateCloudCompute,
        );
        expect(session.executionLocation, model.executionLocation);
        expect(session.provider, 'Apple Private Cloud Compute');
        expect(session.fallbackUsed, isTrue);
        await model.close();
        await host.dispose();
      },
    );

    test('unsupported policies fail explicitly', () async {
      final host = FakeLocalAiHost();
      await expectLater(
        LocalAiModel.create(
          host: host,
          executionPolicy: LocalAiExecutionPolicy.cloudOnly,
        ),
        throwsA(
          isA<LocalAiUnsupportedException>().having(
            (error) => error.capability,
            'capability',
            'executionPolicy',
          ),
        ),
      );
      await host.dispose();
    });
  });

  test('Android cloud model configuration reaches the host', () async {
    final host = FakeLocalAiHost();
    host.policySelections[LocalAiExecutionPolicy.cloudOnly] =
        const LocalAiModelSelection(
          executionLocation: LocalAiExecutionLocation.firebaseAiLogicCloud,
          provider: 'Firebase AI Logic',
        );
    const android = LocalAiAndroidConfiguration(
      cloudModelName: 'gemini-3.5-flash-lite',
    );
    final model = await LocalAiModel.create(
      host: host,
      executionPolicy: LocalAiExecutionPolicy.cloudOnly,
      android: android,
    );
    expect(
      host.modelAndroidConfiguration?.cloudModelName,
      android.cloudModelName,
    );
    await model.close();
    await host.dispose();
  });

  test('response metadata reports the provider that answered', () async {
    final host = FakeLocalAiHost();
    host.policySelections[LocalAiExecutionPolicy.preferOnDevice] =
        const LocalAiModelSelection(
          executionLocation: LocalAiExecutionLocation.firebaseAiLogicCloud,
          provider: 'Firebase AI Logic',
          fallbackUsed: true,
        );
    final model = await LocalAiModel.create(
      host: host,
      executionPolicy: LocalAiExecutionPolicy.preferOnDevice,
    );
    final session = await model.openSession();
    final result = await session.getResponseWithMetadata();
    expect(result.text, 'ok');
    expect(
      result.executionLocation,
      LocalAiExecutionLocation.firebaseAiLogicCloud,
    );
    expect(result.provider, 'Firebase AI Logic');
    await model.close();
    await host.dispose();
  });

  test('PCC capability mapping keeps readiness separate from SDK support', () {
    const capabilities = LocalAiBackendCapabilities(
      backend: LocalAiBackendKind.appleFoundationModels,
      platform: 'ios',
      apiName: 'Apple Foundation Models',
      supportsPrivateCloudCompute: true,
      privateCloudAvailability:
          LocalAiPrivateCloudAvailability.unavailableEntitlementOrConfiguration,
      isConfigured: true,
    );
    expect(capabilities.supportsPrivateCloudCompute, isTrue);
    expect(
      capabilities.privateCloudAvailability,
      LocalAiPrivateCloudAvailability.unavailableEntitlementOrConfiguration,
    );
  });

  test('PCC generation error codes remain stable Dart values', () {
    final error = LocalAiGenerationException(
      'PCC is offline',
      errorCode: 'networkFailure',
    );
    expect(error.code, 'GENERATION_ERROR');
    expect(error.errorCode, 'networkFailure');
  });
}
