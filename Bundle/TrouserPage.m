#import "TrouserPage.h"
#import "TrouserAccessibilityTree.h"

static const NSTimeInterval TrouserCoalesceInterval = 0.1;

static void TrouserFormFocus(WKBundlePageRef, WKBundleNodeHandleRef, WKBundleFrameRef, const void *);
static void TrouserFormFieldChange(WKBundlePageRef, WKBundleNodeHandleRef, WKBundleFrameRef, const void *);
static void TrouserFormAreaChange(WKBundlePageRef, WKBundleNodeHandleRef, WKBundleFrameRef, const void *);
static void TrouserFormSubmit(WKBundlePageRef, WKBundleNodeHandleRef, WKBundleFrameRef, WKBundleFrameRef, WKDictionaryRef, WKTypeRef *, const void *);

@implementation TrouserPage {
    __weak WKWebProcessPlugInBrowserContextController *_controller;
    _WKRemoteObjectInterface *_pageInterface;
    id<TrouserBundleHost> _host;
    TrouserAccessibilityTree *_tree;
    NSMutableDictionary<NSNumber *, NSString *> *_resources;
    BOOL _scheduled;
}

- (instancetype)initWithController:(WKWebProcessPlugInBrowserContextController *)controller
{
    if (!(self = [super init]))
        return nil;
    _controller = controller;
    _tree = [[TrouserAccessibilityTree alloc] initWithPage:controller._bundlePageRef];
    _resources = [NSMutableDictionary dictionary];
    _pageInterface = [_WKRemoteObjectInterface remoteObjectInterfaceWithProtocol:@protocol(TrouserBundlePage)];
    _WKRemoteObjectRegistry *registry = controller._remoteObjectRegistry;
    [registry registerExportedObject:self interface:_pageInterface];
    _host = [registry remoteObjectProxyWithInterface:[_WKRemoteObjectInterface remoteObjectInterfaceWithProtocol:@protocol(TrouserBundleHost)]];
    controller.loadDelegate = self;
    controller._editingDelegate = self;
    [self installFormClient];
    WKBundlePageListenForLayoutMilestones(controller._bundlePageRef, UINT32_MAX);
    [self emit:@"hello" fields:@{ @"version" : @(TrouserBundleProtocolVersion) }];
    return self;
}

- (void)close
{
    [_controller._remoteObjectRegistry unregisterExportedObject:self interface:_pageInterface];
    _host = nil;
}

- (void)installFormClient
{
    WKBundlePageFormClientV2 client = { 0 };
    client.base.version = 2;
    client.base.clientInfo = (__bridge const void *)self;
    client.didFocusTextField = TrouserFormFocus;
    client.textDidChangeInTextField = TrouserFormFieldChange;
    client.textDidChangeInTextArea = TrouserFormAreaChange;
    client.willSubmitForm = TrouserFormSubmit;
    WKBundlePageSetFormClient(_controller._bundlePageRef, &client.base);
}

- (void)emit:(NSString *)type fields:(NSDictionary *)fields
{
    NSMutableDictionary *message = [fields mutableCopy];
    message[@"v"] = @(TrouserBundleProtocolVersion);
    message[@"type"] = type;
    [_host event:[self json:message]];
}

- (NSString *)json:(NSDictionary *)object
{
    if (![NSJSONSerialization isValidJSONObject:object])
        return [self json:@{ @"v" : @(TrouserBundleProtocolVersion), @"type" : @"error", @"error" : @"unencodable message" }];
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
}

- (void)markDirty
{
    if (_scheduled)
        return;
    _scheduled = YES;
    __weak TrouserPage *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TrouserCoalesceInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf flush];
    });
}

- (void)flush
{
    _scheduled = NO;
    NSDictionary *changes = [_tree changes];
    if (changes)
        [self emit:@"dom.changes" fields:changes];
}

- (void)command:(NSString *)json reply:(void (^)(NSString *))reply
{
    NSDictionary *command = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    NSString *name = [command isKindOfClass:[NSDictionary class]] ? command[@"command"] : nil;
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:@(TrouserBundleProtocolVersion) forKey:@"v"];
    if (![command[@"v"] isEqual:@(TrouserBundleProtocolVersion)])
        result[@"error"] = @"unsupported protocol version";
    else if ([name isEqual:@"snapshot"])
        [result addEntriesFromDictionary:[_tree snapshot]];
    else if ([name isEqual:@"hitTest"])
        result[@"hit"] = [_tree hitTest:CGPointMake([command[@"x"] doubleValue], [command[@"y"] doubleValue])] ?: [NSNull null];
    else
        result[@"error"] = @"unknown command";
    reply([self json:result]);
}

- (NSString *)frameKind:(WKWebProcessPlugInFrame *)frame
{
    return frame.isMainFrame ? @"main" : @"sub";
}

- (void)load:(NSString *)type frame:(WKWebProcessPlugInFrame *)frame
{
    [self emit:type fields:@{ @"frame" : [self frameKind:frame], @"url" : frame.URL.absoluteString ?: @"" }];
}

- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller didStartProvisionalLoadForFrame:(WKWebProcessPlugInFrame *)frame
{
    [self load:@"load.start" frame:frame];
}

- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller didCommitLoadForFrame:(WKWebProcessPlugInFrame *)frame
{
    if (frame.isMainFrame)
        [_tree reset];
    [self load:@"load.commit" frame:frame];
}

- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller didFinishDocumentLoadForFrame:(WKWebProcessPlugInFrame *)frame
{
    [self load:@"load.domReady" frame:frame];
    [self markDirty];
}

- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller didFinishLoadForFrame:(WKWebProcessPlugInFrame *)frame
{
    [self load:@"load.finish" frame:frame];
    [self markDirty];
}

- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller didFailLoadWithErrorForFrame:(WKWebProcessPlugInFrame *)frame error:(NSError *)error
{
    [self emit:@"load.fail" fields:@{ @"frame" : [self frameKind:frame], @"url" : frame.URL.absoluteString ?: @"", @"error" : error.localizedDescription ?: @"" }];
}

- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller didSameDocumentNavigation:(NSInteger)navigationType forFrame:(WKWebProcessPlugInFrame *)frame
{
    [self load:@"load.sameDocument" frame:frame];
    [self markDirty];
}

- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller didLayoutForFrame:(WKWebProcessPlugInFrame *)frame
{
    [self markDirty];
}

- (void)_webProcessPlugInBrowserContextControllerDidChangeByEditing:(WKWebProcessPlugInBrowserContextController *)controller
{
    [self markDirty];
}

- (NSURLRequest *)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller frame:(WKWebProcessPlugInFrame *)frame willSendRequestForResource:(uint64_t)resource request:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse
{
    NSString *url = request.URL.absoluteString ?: @"";
    _resources[@(resource)] = url;
    [self emit:@"net.willSend" fields:@{ @"id" : @(resource), @"method" : request.HTTPMethod ?: @"GET", @"url" : url, @"redirect" : redirectResponse ? @YES : @NO }];
    return request;
}

- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller frame:(WKWebProcessPlugInFrame *)frame didReceiveResponse:(NSURLResponse *)response forResource:(uint64_t)resource
{
    NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    [self emit:@"net.response" fields:@{ @"id" : @(resource), @"url" : _resources[@(resource)] ?: response.URL.absoluteString ?: @"", @"status" : @(status), @"mime" : response.MIMEType ?: @"" }];
}

- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller frame:(WKWebProcessPlugInFrame *)frame didFinishLoadForResource:(uint64_t)resource
{
    NSString *url = _resources[@(resource)] ?: @"";
    [_resources removeObjectForKey:@(resource)];
    [self emit:@"net.finish" fields:@{ @"id" : @(resource), @"url" : url }];
}

- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller frame:(WKWebProcessPlugInFrame *)frame didFailLoadForResource:(uint64_t)resource error:(NSError *)error
{
    NSString *url = _resources[@(resource)] ?: @"";
    [_resources removeObjectForKey:@(resource)];
    [self emit:@"net.fail" fields:@{ @"id" : @(resource), @"url" : url, @"error" : error.localizedDescription ?: @"" }];
}

- (void)form:(NSString *)type field:(WKBundleNodeHandleRef)field kind:(NSString *)kind
{
    WKRect bounds = WKBundleNodeHandleGetElementBounds(field);
    NSArray *frame = @[ @(round(bounds.origin.x)), @(round(bounds.origin.y)), @(round(bounds.size.width)), @(round(bounds.size.height)) ];
    [self emit:type fields:@{ @"frame" : frame, @"kind" : kind }];
    [self markDirty];
}

- (void)formSubmittedWithFields:(NSUInteger)count
{
    [self emit:@"form.submit" fields:@{ @"fields" : @(count) }];
}

@end

static TrouserPage *TrouserPageFrom(const void *info)
{
    return (__bridge TrouserPage *)info;
}

static void TrouserFormFocus(WKBundlePageRef page, WKBundleNodeHandleRef field, WKBundleFrameRef frame, const void *info)
{
    [TrouserPageFrom(info) form:@"form.focus" field:field kind:@"field"];
}

static void TrouserFormFieldChange(WKBundlePageRef page, WKBundleNodeHandleRef field, WKBundleFrameRef frame, const void *info)
{
    [TrouserPageFrom(info) form:@"form.change" field:field kind:@"field"];
}

static void TrouserFormAreaChange(WKBundlePageRef page, WKBundleNodeHandleRef field, WKBundleFrameRef frame, const void *info)
{
    [TrouserPageFrom(info) form:@"form.change" field:field kind:@"area"];
}

static void TrouserFormSubmit(WKBundlePageRef page, WKBundleNodeHandleRef form, WKBundleFrameRef frame, WKBundleFrameRef source, WKDictionaryRef values, WKTypeRef *userData, const void *info)
{
    WKArrayRef keys = WKDictionaryCopyKeys(values);
    size_t count = keys ? WKArrayGetSize(keys) : 0;
    if (keys)
        WKRelease(keys);
    [TrouserPageFrom(info) formSubmittedWithFields:count];
}
