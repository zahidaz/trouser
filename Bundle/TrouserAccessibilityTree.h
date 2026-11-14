#import "WebKitBundle.h"

NS_ASSUME_NONNULL_BEGIN

@interface TrouserAccessibilityTree : NSObject
@property (nonatomic, readonly) NSInteger revision;
- (instancetype)initWithPage:(WKBundlePageRef)page NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (NSDictionary *)snapshot;
- (nullable NSDictionary *)changes;
- (nullable NSDictionary *)hitTest:(CGPoint)point;
- (void)reset;
@end

NS_ASSUME_NONNULL_END
