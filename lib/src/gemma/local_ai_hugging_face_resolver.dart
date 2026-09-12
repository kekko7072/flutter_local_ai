import 'package:flutter_gemma/core/domain/platform_types.dart'
    show PreferredBackend;
import 'package:flutter_gemma/core/model.dart' show ModelFileType;
import 'package:flutter_gemma/core/registry/hugging_face_resolver.dart'
    show HuggingFaceResolver, ResolvedHfModel;

/// Claims the `ModelFileType.builtIn` Hugging Face slot so that resolving one
/// fails with a clear explanation instead of core's generic "no resolver
/// registered" error.
///
/// There is nothing to resolve: the OS owns the weights and a `builtIn`
/// install downloads no file. Auto-registered by [LocalAiEngine], which
/// implements `HuggingFaceResolverSource`.
class LocalAiHuggingFaceResolver implements HuggingFaceResolver {
  const LocalAiHuggingFaceResolver();

  @override
  String get name => 'local-ai-huggingface';

  @override
  int get priority => 0;

  @override
  bool canResolve(String repo, {ModelFileType? fileType}) =>
      fileType == ModelFileType.builtIn;

  @override
  Future<ResolvedHfModel> resolve(
    String repo, {
    String? token,
    String? platform,
    PreferredBackend? preferredBackend,
  }) async {
    throw UnsupportedError(
      'Built-in OS models are provided by the operating system — there is no '
      'Hugging Face file to resolve for "$repo". Install one with '
      'ModelFileType.builtIn instead (see LocalAiModels); nothing is '
      'downloaded.',
    );
  }
}
