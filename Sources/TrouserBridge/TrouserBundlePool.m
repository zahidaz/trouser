#import "TrouserBridge.h"
#import "TrouserBundleProtocol.h"

@interface _WKProcessPoolConfiguration : NSObject
@property (nonatomic, copy) NSURL *injectedBundleURL;
@end

@interface WKProcessPool (TrouserPrivate)
- (instancetype)_initWithConfiguration:(_WKProcessPoolConfiguration *)configuration __attribute__((objc_method_family(init)));
- (void)_setObject:(id<NSCopying, NSSecureCoding>)object forBundleParameter:(NSString *)parameter;
@end

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@implementation TrouserBundlePool {
    WKProcessPool *_pool;
}

- (instancetype)initWithBundleURL:(NSURL *)bundleURL
{
    if (!(self = [super init]))
        return nil;
    _WKProcessPoolConfiguration *configuration = [[_WKProcessPoolConfiguration alloc] init];
    configuration.injectedBundleURL = bundleURL;
    _pool = [[WKProcessPool alloc] _initWithConfiguration:configuration];
    [_pool _setObject:@(TrouserBundleProtocolVersion) forBundleParameter:TrouserBundleProtocolParameter];
    return self;
}

- (void)configure:(WKWebViewConfiguration *)configuration
{
    configuration.processPool = _pool;
}

- (BOOL)isConfigured:(WKWebViewConfiguration *)configuration
{
    return configuration.processPool == _pool;
}

@end

#pragma clang diagnostic pop
