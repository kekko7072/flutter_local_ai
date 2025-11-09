#import "FlutterLocalAiPlugin.h"
#if __has_include(<flutter_local_ai/flutter_local_ai-Swift.h>)
#import <flutter_local_ai/flutter_local_ai-Swift.h>
#else
#import "flutter_local_ai-Swift.h"
#endif

@implementation FlutterLocalAiPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftFlutterLocalAiPlugin registerWithRegistrar:registrar];
}
@end
