#import "WebKitBundle.h"
#import "TrouserBundleProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface TrouserPage : NSObject <TrouserBundlePage, WKWebProcessPlugInLoadDelegate, WKWebProcessPlugInEditingDelegate>
- (instancetype)initWithController:(WKWebProcessPlugInBrowserContextController *)controller NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)close;
@end

NS_ASSUME_NONNULL_END
