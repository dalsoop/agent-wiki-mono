#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "FleetDeskHookC.h"
#include <pwd.h>
#include <unistd.h>

static IMP original_setActivationPolicy;

static NSArray<NSString *> *FleetDeskHomeCandidates(void) {
    NSMutableArray<NSString *> *homes = [NSMutableArray array];
    struct passwd *pw = getpwuid(getuid());
    if (pw != NULL && pw->pw_dir != NULL) {
        [homes addObject:[NSString stringWithUTF8String:pw->pw_dir]];
    }
    NSString *nsHome = NSHomeDirectory();
    if (nsHome.length > 0) { [homes addObject:nsHome]; }
    NSString *env = [[[NSProcessInfo processInfo] environment] objectForKey:@"HOME"];
    if ([env isKindOfClass:[NSString class]] && env.length > 0) {
        [homes addObject:env];
    }
    return homes;
}

static NSDictionary *FleetDeskReadFlag(void) {
    for (NSString *home in FleetDeskHomeCandidates()) {
        NSString *path = [home stringByAppendingPathComponent:@".swift-app-state/fleet-desk.json"];
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (data == nil) { continue; }
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:[NSDictionary class]]) {
            return json;
        }
    }
    return nil;
}

static NSString *FleetDeskBundleID(void) {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bid = bundle.bundleIdentifier;
    if (bid.length > 0) { return bid; }
    id fromPlist = [bundle objectForInfoDictionaryKey:@"CFBundleIdentifier"];
    if ([fromPlist isKindOfClass:[NSString class]]) {
        return fromPlist;
    }
    return @"";
}

static BOOL FleetDeskIsGUIAppProcess(void) {
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    NSString *exec = args.count > 0 ? args[0] : @"";
    if ([exec containsString:@"xctest"] || [exec containsString:@"swiftpm-testing"]) {
        return NO;
    }
    if ([exec containsString:@"/Contents/Helpers/"]) {
        return NO;
    }
    return [exec containsString:@"/Contents/MacOS/"];
}

/// Swift `FleetDeskPolicy` / `FleetDeskIdentity` 와 같은 규칙. dyld·swizzle 경로에서는
/// Swift 런타임을 부르지 않는다(생성자에서 Swift 락을 잡던 사고).
bool FleetDeskShouldForceAccessory(void) {
    NSDictionary *dict = FleetDeskReadFlag();
    if (dict == nil) { return NO; }
    id hide = dict[@"hideFleetDockIcons"];
    BOOL hideOn = [hide isKindOfClass:[NSNumber class]] ? [hide boolValue] : NO;
    if (!hideOn) { return NO; }

    NSString *bid = FleetDeskBundleID();
    NSString *low = bid.lowercaseString;
    if (low.length == 0) { return NO; }
    if ([low containsString:@"agent-apps-bar"] || [low containsString:@"agentappsbar"]) {
        return NO;
    }
    if (![low hasPrefix:@"net.ranode."] && ![low hasPrefix:@"com.dalsoop."]) {
        return NO;
    }

    NSArray *allow = nil;
    id rawAllow = dict[@"dockBundleIds"];
    if ([rawAllow isKindOfClass:[NSArray class]]) {
        allow = rawAllow;
    } else {
        allow = @[
            @"net.ranode.agent-worker-orchestrator",
            @"net.ranode.agent-chat",
        ];
    }
    for (id item in allow) {
        if ([item isKindOfClass:[NSString class]] &&
            [((NSString *)item).lowercaseString isEqualToString:low]) {
            return NO;
        }
    }
    return YES;
}

static BOOL FleetDeskSwizzledSetActivationPolicy(
    id self,
    SEL sel,
    NSApplicationActivationPolicy policy
) {
    if (policy == NSApplicationActivationPolicyRegular && FleetDeskShouldForceAccessory()) {
        policy = NSApplicationActivationPolicyAccessory;
    }
    if (original_setActivationPolicy == NULL) {
        return NO;
    }
    typedef BOOL (*Orig)(id, SEL, NSApplicationActivationPolicy);
    return ((Orig)original_setActivationPolicy)(self, sel, policy);
}

__attribute__((constructor))
static void fleet_desk_ctor(void) {
    if (!FleetDeskIsGUIAppProcess()) {
        return;
    }
    Class cls = NSClassFromString(@"NSApplication");
    if (cls == Nil) { return; }
    Method method = class_getInstanceMethod(cls, @selector(setActivationPolicy:));
    if (method == NULL) { return; }
    original_setActivationPolicy = method_setImplementation(
        method,
        (IMP)FleetDeskSwizzledSetActivationPolicy
    );

    [[NSNotificationCenter defaultCenter]
        addObserverForName:NSApplicationWillFinishLaunchingNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
                    (void)note;
                    if (FleetDeskShouldForceAccessory()) {
                        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
                    }
                    FleetDeskInstallActivationHook();
                }];
}

void FleetDeskActivationHookForceLink(void) {}
#else
#include "FleetDeskHookC.h"
void FleetDeskActivationHookForceLink(void) {}
void FleetDeskInstallActivationHook(void) {}
bool FleetDeskShouldForceAccessory(void) { return false; }
#endif
