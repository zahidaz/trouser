#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface _WKRemoteObjectInterface : NSObject
+ (instancetype)remoteObjectInterfaceWithProtocol:(Protocol *)protocol;
@end

@interface _WKRemoteObjectRegistry : NSObject
- (void)registerExportedObject:(id)object interface:(_WKRemoteObjectInterface *)interface;
- (void)unregisterExportedObject:(id)object interface:(_WKRemoteObjectInterface *)interface;
- (id)remoteObjectProxyWithInterface:(_WKRemoteObjectInterface *)interface;
@end

NS_ASSUME_NONNULL_END
