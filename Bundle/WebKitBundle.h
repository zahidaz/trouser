#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import "WebKitRemoteObjects.h"

typedef const struct OpaqueWKBundlePage *WKBundlePageRef;
typedef const struct OpaqueWKBundleFrame *WKBundleFrameRef;
typedef const struct OpaqueWKBundleNodeHandle *WKBundleNodeHandleRef;
typedef const struct OpaqueWKDictionary *WKDictionaryRef;
typedef const struct OpaqueWKArray *WKArrayRef;
typedef const void *WKTypeRef;
typedef struct {
    struct { double x, y; } origin;
    struct { double width, height; } size;
} WKRect;

WK_EXTERN WKRect WKBundleNodeHandleGetElementBounds(WKBundleNodeHandleRef);
WK_EXTERN WKArrayRef WKDictionaryCopyKeys(WKDictionaryRef);
WK_EXTERN size_t WKArrayGetSize(WKArrayRef);
WK_EXTERN void WKRelease(WKTypeRef);
WK_EXTERN void WKBundlePageListenForLayoutMilestones(WKBundlePageRef, uint32_t);
WK_EXTERN void WKAccessibilityEnable(void);
WK_EXTERN void *WKAccessibilityFocusedObject(WKBundlePageRef);

typedef struct {
    int version;
    const void *clientInfo;
} WKBundlePageFormClientBase;

typedef struct {
    WKBundlePageFormClientBase base;
    void (*textFieldDidBeginEditing)(WKBundlePageRef, WKBundleNodeHandleRef, WKBundleFrameRef, const void *);
    void (*textFieldDidEndEditing)(WKBundlePageRef, WKBundleNodeHandleRef, WKBundleFrameRef, const void *);
    void (*textDidChangeInTextField)(WKBundlePageRef, WKBundleNodeHandleRef, WKBundleFrameRef, const void *);
    void (*textDidChangeInTextArea)(WKBundlePageRef, WKBundleNodeHandleRef, WKBundleFrameRef, const void *);
    bool (*shouldPerformActionInTextField)(WKBundlePageRef, WKBundleNodeHandleRef, int, WKBundleFrameRef, const void *);
    void (*willSubmitForm)(WKBundlePageRef, WKBundleNodeHandleRef, WKBundleFrameRef, WKBundleFrameRef, WKDictionaryRef, WKTypeRef *, const void *);
    void (*willSendSubmitEvent)(WKBundlePageRef, WKBundleNodeHandleRef, WKBundleFrameRef, WKBundleFrameRef, WKDictionaryRef, const void *);
    void (*didFocusTextField)(WKBundlePageRef, WKBundleNodeHandleRef, WKBundleFrameRef, const void *);
    bool (*shouldNotifyOnFormChanges)(WKBundlePageRef, const void *);
    void (*didAssociateFormControls)(WKBundlePageRef, WKArrayRef, const void *);
} WKBundlePageFormClientV2;

WK_EXTERN void WKBundlePageSetFormClient(WKBundlePageRef, const WKBundlePageFormClientBase *);

@class WKWebProcessPlugInController, WKWebProcessPlugInBrowserContextController, WKWebProcessPlugInFrame;

@protocol WKWebProcessPlugIn <NSObject>
@optional
- (void)webProcessPlugIn:(WKWebProcessPlugInController *)plugInController initializeWithObject:(id)initializationObject;
- (void)webProcessPlugIn:(WKWebProcessPlugInController *)plugInController didCreateBrowserContextController:(WKWebProcessPlugInBrowserContextController *)browserContextController;
- (void)webProcessPlugIn:(WKWebProcessPlugInController *)plugInController willDestroyBrowserContextController:(WKWebProcessPlugInBrowserContextController *)browserContextController;
@end

@interface WKWebProcessPlugInController : NSObject
@property (readonly) id parameters;
@end

@interface WKWebProcessPlugInFrame : NSObject
@property (nonatomic, readonly) NSURL *URL;
@property (nonatomic, readonly) BOOL isMainFrame;
@end

@protocol WKWebProcessPlugInLoadDelegate <NSObject>
@optional
- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller didStartProvisionalLoadForFrame:(WKWebProcessPlugInFrame *)frame;
- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller didCommitLoadForFrame:(WKWebProcessPlugInFrame *)frame;
- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller didFinishDocumentLoadForFrame:(WKWebProcessPlugInFrame *)frame;
- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller didFinishLoadForFrame:(WKWebProcessPlugInFrame *)frame;
- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller didFailLoadWithErrorForFrame:(WKWebProcessPlugInFrame *)frame error:(NSError *)error;
- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller didSameDocumentNavigation:(NSInteger)navigationType forFrame:(WKWebProcessPlugInFrame *)frame;
- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller didLayoutForFrame:(WKWebProcessPlugInFrame *)frame;
- (NSURLRequest *)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller frame:(WKWebProcessPlugInFrame *)frame willSendRequestForResource:(uint64_t)resource request:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse;
- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller frame:(WKWebProcessPlugInFrame *)frame didReceiveResponse:(NSURLResponse *)response forResource:(uint64_t)resource;
- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller frame:(WKWebProcessPlugInFrame *)frame didFinishLoadForResource:(uint64_t)resource;
- (void)webProcessPlugInBrowserContextController:(WKWebProcessPlugInBrowserContextController *)controller frame:(WKWebProcessPlugInFrame *)frame didFailLoadForResource:(uint64_t)resource error:(NSError *)error;
@end

@protocol WKWebProcessPlugInEditingDelegate <NSObject>
@optional
- (void)_webProcessPlugInBrowserContextControllerDidChangeByEditing:(WKWebProcessPlugInBrowserContextController *)controller;
@end

@interface WKWebProcessPlugInBrowserContextController : NSObject
@property (weak) id<WKWebProcessPlugInLoadDelegate> loadDelegate;
@property (nonatomic, readonly) WKBundlePageRef _bundlePageRef;
@property (nonatomic, readonly) _WKRemoteObjectRegistry *_remoteObjectRegistry;
@property (weak, setter=_setEditingDelegate:) id<WKWebProcessPlugInEditingDelegate> _editingDelegate;
@end
