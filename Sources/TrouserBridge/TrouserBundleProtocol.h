#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const TrouserBundleProtocolParameter = @"trouser.protocol";
static const NSInteger TrouserBundleProtocolVersion = 1;

@protocol TrouserBundleHost <NSObject>
- (void)event:(NSString *)json;
@end

@protocol TrouserBundlePage <NSObject>
- (void)command:(NSString *)json reply:(void (^)(NSString *json))reply;
@end

NS_ASSUME_NONNULL_END
