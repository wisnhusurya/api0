#import "Api0Plugin.h"
#if __has_include(<api0/api0-Swift.h>)
#import <api0/api0-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "api0-Swift.h"
#endif

@implementation Api0Plugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftApi0Plugin registerWithRegistrar:registrar];
}
@end
