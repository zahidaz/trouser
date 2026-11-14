#import "TrouserBridge.h"
#import "TrouserBundleProtocol.h"
#import "WebKitRemoteObjects.h"

@interface WKWebView (TrouserPrivate)
@property (nonatomic, readonly) _WKRemoteObjectRegistry *_remoteObjectRegistry;
@end

@interface TrouserBundleChannel () <TrouserBundleHost>
@end

@implementation TrouserBundleChannel {
    _WKRemoteObjectRegistry *_registry;
    _WKRemoteObjectInterface *_hostInterface;
    id<TrouserBundlePage> _page;
    void (^_events)(NSString *);
}

- (instancetype)initWithWebView:(WKWebView *)webView events:(void (^)(NSString *))events
{
    if (!(self = [super init]))
        return nil;
    _events = [events copy];
    _registry = webView._remoteObjectRegistry;
    _hostInterface = [_WKRemoteObjectInterface remoteObjectInterfaceWithProtocol:@protocol(TrouserBundleHost)];
    [_registry registerExportedObject:self interface:_hostInterface];
    _page = [_registry remoteObjectProxyWithInterface:[_WKRemoteObjectInterface remoteObjectInterfaceWithProtocol:@protocol(TrouserBundlePage)]];
    return self;
}

- (void)event:(NSString *)json
{
    void (^events)(NSString *) = _events;
    if (!events)
        return;
    if (NSThread.isMainThread)
        events(json);
    else
        dispatch_async(dispatch_get_main_queue(), ^{
            events(json);
        });
}

- (void)send:(NSString *)json timeout:(NSTimeInterval)timeout reply:(void (^)(NSString *))reply
{
    if (!_page) {
        reply(nil);
        return;
    }
    __block BOOL answered = NO;
    void (^answer)(NSString *) = ^(NSString *result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (answered)
                return;
            answered = YES;
            reply(result);
        });
    };
    [_page command:json reply:^(NSString *result) {
        answer(result);
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        answer(nil);
    });
}

- (void)close
{
    if (!_page)
        return;
    [_registry unregisterExportedObject:self interface:_hostInterface];
    _page = nil;
    _events = nil;
}

@end
