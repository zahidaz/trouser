#import "TrouserAccessibilityTree.h"

static const NSUInteger TrouserNodeLimit = 10000;
static const NSUInteger TrouserDepthLimit = 200;

static NSSet<NSString *> *TrouserStructuralRoles(void)
{
    static NSSet *roles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        roles = [NSSet setWithArray:@[ @"AXGroup", @"AXWebArea", @"AXScrollArea", @"AXList", @"AXUnknown", @"AXRow", @"AXColumn", @"AXCell", @"AXTable", @"AXOutline", @"AXSplitGroup", @"AXLayoutArea", @"AXLayoutItem", @"AXListMarker", @"AXDescriptionList", @"AXRadioGroup", @"AXTabGroup", @"AXToolbar", @"AXMenu", @"AXMenuBar" ]];
    });
    return roles;
}

static NSSet<NSString *> *TrouserLeafRoles(void)
{
    static NSSet *roles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        roles = [NSSet setWithArray:@[ @"AXTextField", @"AXTextArea", @"AXPopUpButton", @"AXComboBox", @"AXSlider", @"AXIncrementor", @"AXButton", @"AXMenuButton", @"AXCheckBox", @"AXRadioButton", @"AXImage", @"AXDisclosureTriangle" ]];
    });
    return roles;
}

static NSArray *TrouserFrame(NSRect rect)
{
    if (!isfinite(rect.origin.x) || !isfinite(rect.origin.y) || !isfinite(rect.size.width) || !isfinite(rect.size.height))
        return nil;
    return @[ @(round(rect.origin.x)), @(round(rect.origin.y)), @(round(rect.size.width)), @(round(rect.size.height)) ];
}

@implementation TrouserAccessibilityTree {
    WKBundlePageRef _page;
    NSMapTable<id, NSNumber *> *_keys;
    NSInteger _nextKey;
    NSDictionary<NSString *, NSDictionary *> *_nodes;
    NSArray<NSString *> *_order;
    NSHashTable *_visited;
    NSRect _viewport;
}

- (instancetype)initWithPage:(WKBundlePageRef)page
{
    if (!(self = [super init]))
        return nil;
    _page = page;
    _keys = [NSMapTable weakToStrongObjectsMapTable];
    _nodes = @{};
    _order = @[];
    WKAccessibilityEnable();
    return self;
}

- (void)reset
{
    _nodes = @{};
    _order = @[];
    _revision = 0;
}

- (NSDictionary *)snapshot
{
    NSArray *nodes = [self walk];
    [self adopt:nodes];
    return @{ @"revision" : @(_revision), @"nodes" : nodes };
}

- (NSDictionary *)changes
{
    NSInteger base = _revision;
    NSDictionary *previous = _nodes;
    NSArray *previousOrder = _order;
    NSArray *nodes = [self walk];
    [self adopt:nodes];
    if (_revision == base)
        return nil;
    NSMutableArray *upsert = [NSMutableArray array];
    for (NSDictionary *node in nodes) {
        if (![previous[node[@"key"]] isEqual:node])
            [upsert addObject:node];
    }
    NSMutableArray *remove = [NSMutableArray array];
    for (NSString *key in previousOrder) {
        if (!_nodes[key])
            [remove addObject:key];
    }
    NSMutableDictionary *changes = [@{ @"base" : @(base), @"revision" : @(_revision), @"upsert" : upsert, @"remove" : remove } mutableCopy];
    if (![_order isEqualToArray:previousOrder])
        changes[@"order"] = _order;
    return changes;
}

- (void)adopt:(NSArray<NSDictionary *> *)nodes
{
    NSMutableDictionary *byKey = [NSMutableDictionary dictionaryWithCapacity:nodes.count];
    NSMutableArray *order = [NSMutableArray arrayWithCapacity:nodes.count];
    for (NSDictionary *node in nodes) {
        byKey[node[@"key"]] = node;
        [order addObject:node[@"key"]];
    }
    if ([byKey isEqualToDictionary:_nodes] && [order isEqualToArray:_order])
        return;
    _nodes = byKey;
    _order = order;
    _revision += 1;
}

- (NSDictionary *)hitTest:(CGPoint)point
{
    id root = [self root];
    id hit = [self attempt:^id { return [root accessibilityHitTest:point]; }];
    for (id node = hit; node && node != root; node = [self value:node attribute:NSAccessibilityParentAttribute]) {
        NSString *role = [self value:node attribute:NSAccessibilityRoleAttribute];
        if (![role isKindOfClass:[NSString class]] || [TrouserStructuralRoles() containsObject:role] || [role isEqual:@"AXStaticText"])
            continue;
        NSString *label = [self label:node];
        if (!label.length)
            continue;
        NSMutableDictionary *result = [@{ @"role" : role, @"label" : label } mutableCopy];
        NSValue *frame = [self value:node attribute:@"AXRelativeFrame"];
        if ([frame isKindOfClass:[NSValue class]])
            result[@"frame"] = TrouserFrame(frame.rectValue);
        return result;
    }
    return nil;
}

- (id)root
{
    id node = (__bridge id)WKAccessibilityFocusedObject(_page);
    id root = nil;
    while (node) {
        if ([[self value:node attribute:NSAccessibilityRoleAttribute] isEqual:@"AXWebArea"])
            root = node;
        id parent = [self value:node attribute:NSAccessibilityParentAttribute];
        node = [parent isKindOfClass:[NSString class]] || parent == node ? nil : parent;
    }
    return root;
}

- (NSArray<NSDictionary *> *)walk
{
    NSMutableArray *nodes = [NSMutableArray array];
    id root = [self root];
    if (!root)
        return nodes;
    _visited = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    _viewport = [self viewportOf:root];
    [self collectChildrenOf:root parent:nil depth:0 into:nodes];
    _visited = nil;
    return nodes;
}

- (NSRect)viewportOf:(id)root
{
    NSValue *frame = [self value:[self value:root attribute:NSAccessibilityParentAttribute] attribute:@"AXRelativeFrame"];
    return [frame isKindOfClass:[NSValue class]] ? frame.rectValue : NSZeroRect;
}

- (BOOL)isOnScreen:(id)object
{
    NSValue *frame = [self value:object attribute:@"AXRelativeFrame"];
    return [frame isKindOfClass:[NSValue class]] && NSIntersectsRect(frame.rectValue, _viewport);
}

- (void)collectChildrenOf:(id)object parent:(NSString *)parent depth:(NSUInteger)depth into:(NSMutableArray *)nodes
{
    if (depth > TrouserDepthLimit)
        return;
    NSArray *children = [self value:object attribute:NSAccessibilityChildrenAttribute];
    if (![children isKindOfClass:[NSArray class]])
        return;
    for (id child in children) {
        if ([_visited containsObject:child])
            continue;
        [_visited addObject:child];
        if (nodes.count >= TrouserNodeLimit && ![self isOnScreen:child])
            continue;
        NSString *role = [self value:child attribute:NSAccessibilityRoleAttribute];
        if (![role isKindOfClass:[NSString class]])
            continue;
        if ([TrouserStructuralRoles() containsObject:role]) {
            [self collectChildrenOf:child parent:parent depth:depth + 1 into:nodes];
            continue;
        }
        NSDictionary *node = [self describe:child role:role parent:parent];
        [nodes addObject:node];
        if (![TrouserLeafRoles() containsObject:role])
            [self collectChildrenOf:child parent:node[@"key"] depth:depth + 1 into:nodes];
    }
}

- (NSDictionary *)describe:(id)object role:(NSString *)role parent:(NSString *)parent
{
    NSMutableDictionary *node = [NSMutableDictionary dictionaryWithObjectsAndKeys:[self keyFor:object], @"key", role, @"role", nil];
    node[@"parent"] = parent;
    NSValue *frame = [self value:object attribute:@"AXRelativeFrame"];
    if ([frame isKindOfClass:[NSValue class]])
        node[@"frame"] = TrouserFrame(frame.rectValue);
    NSString *subrole = [self string:object attribute:NSAccessibilitySubroleAttribute];
    node[@"subrole"] = subrole;
    id value = [self value:object attribute:NSAccessibilityValueAttribute];
    if ([role isEqual:@"AXStaticText"]) {
        node[@"value"] = [value isKindOfClass:[NSString class]] ? value : nil;
        return node;
    }
    node[@"title"] = [self string:object attribute:NSAccessibilityTitleAttribute];
    node[@"description"] = [self string:object attribute:NSAccessibilityDescriptionAttribute];
    node[@"dom"] = [self string:object attribute:@"AXDOMIdentifier"];
    if ([role isEqual:@"AXHeading"])
        return node;
    BOOL secure = [subrole isEqual:@"AXSecureTextField"];
    if ([value isKindOfClass:[NSString class]] && [value length] && !secure)
        node[@"value"] = value;
    else if ([value isKindOfClass:[NSNumber class]] && isfinite([value doubleValue]))
        node[@"number"] = value;
    NSURL *url = [self value:object attribute:NSAccessibilityURLAttribute];
    if ([url isKindOfClass:[NSURL class]])
        node[@"url"] = url.absoluteString;
    [self addStatesOf:object to:node];
    return node;
}

- (void)addStatesOf:(id)object to:(NSMutableDictionary *)node
{
    NSArray *names = [self attempt:^id { return [object accessibilityAttributeNames]; }];
    BOOL enabled = [[self value:object attribute:NSAccessibilityEnabledAttribute] boolValue];
    if (!enabled)
        node[@"disabled"] = @YES;
    if ([[self value:object attribute:NSAccessibilityFocusedAttribute] boolValue])
        node[@"focused"] = @YES;
    if ([[self value:object attribute:@"AXRequired"] boolValue])
        node[@"required"] = @YES;
    if ([[self value:object attribute:NSAccessibilitySelectedAttribute] boolValue])
        node[@"selected"] = @YES;
    if ([names containsObject:NSAccessibilityExpandedAttribute])
        node[@"expanded"] = @([[self value:object attribute:NSAccessibilityExpandedAttribute] boolValue]);
    NSString *invalid = [self string:object attribute:@"AXInvalid"];
    if (invalid.length && ![invalid isEqual:@"false"])
        node[@"invalid"] = @YES;
    node[@"placeholder"] = [self string:object attribute:NSAccessibilityPlaceholderValueAttribute];
    if (enabled && [@[ @"AXTextField", @"AXTextArea" ] containsObject:node[@"role"]] && ![[self attempt:^id { return @([object accessibilityIsAttributeSettable:NSAccessibilityValueAttribute]); }] boolValue])
        node[@"readonly"] = @YES;
}

- (NSString *)label:(id)object
{
    for (NSString *attribute in @[ NSAccessibilityTitleAttribute, NSAccessibilityDescriptionAttribute, NSAccessibilityValueAttribute ]) {
        NSString *text = [self string:object attribute:attribute];
        if (text.length)
            return text;
    }
    return nil;
}

- (NSString *)keyFor:(id)object
{
    NSNumber *key = [_keys objectForKey:object];
    if (!key) {
        _nextKey += 1;
        key = @(_nextKey);
        [_keys setObject:key forKey:object];
    }
    return [NSString stringWithFormat:@"n%@", key];
}

- (NSString *)string:(id)object attribute:(NSString *)attribute
{
    id value = [self value:object attribute:attribute];
    return [value isKindOfClass:[NSString class]] && [value length] ? value : nil;
}

- (id)value:(id)object attribute:(NSString *)attribute
{
    return [self attempt:^id { return [object accessibilityAttributeValue:attribute]; }];
}

- (id)attempt:(id (^)(void))read
{
    @try {
        return read();
    } @catch (NSException *exception) {
        return nil;
    }
}

@end
