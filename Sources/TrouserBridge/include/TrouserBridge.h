#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_UI_ACTOR
@interface TrouserBundlePool : NSObject
- (instancetype)initWithBundleURL:(NSURL *)bundleURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)configure:(WKWebViewConfiguration *)configuration;
- (BOOL)isConfigured:(WKWebViewConfiguration *)configuration;
@end

NS_SWIFT_UI_ACTOR
@interface TrouserBundleChannel : NSObject
- (instancetype)initWithWebView:(WKWebView *)webView events:(void (^)(NSString *json))events NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)send:(NSString *)json timeout:(NSTimeInterval)timeout reply:(void (^)(NSString *_Nullable json))reply;
- (void)close;
@end

NS_ASSUME_NONNULL_END
