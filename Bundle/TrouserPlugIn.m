#import "TrouserPage.h"

@interface TrouserPlugIn : NSObject <WKWebProcessPlugIn>
@end

@implementation TrouserPlugIn {
    NSMapTable<WKWebProcessPlugInBrowserContextController *, TrouserPage *> *_pages;
    BOOL _compatible;
}

- (void)webProcessPlugIn:(WKWebProcessPlugInController *)plugInController initializeWithObject:(id)initializationObject
{
    _pages = [NSMapTable weakToStrongObjectsMapTable];
    _compatible = [[plugInController.parameters valueForKey:TrouserBundleProtocolParameter] isEqual:@(TrouserBundleProtocolVersion)];
}

- (void)webProcessPlugIn:(WKWebProcessPlugInController *)plugInController didCreateBrowserContextController:(WKWebProcessPlugInBrowserContextController *)browserContextController
{
    if (_compatible)
        [_pages setObject:[[TrouserPage alloc] initWithController:browserContextController] forKey:browserContextController];
}

- (void)webProcessPlugIn:(WKWebProcessPlugInController *)plugInController willDestroyBrowserContextController:(WKWebProcessPlugInBrowserContextController *)browserContextController
{
    [[_pages objectForKey:browserContextController] close];
    [_pages removeObjectForKey:browserContextController];
}

@end
