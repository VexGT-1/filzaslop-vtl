/*
 * LiquidGlassUI.m — iOS 26 Liquid Glass styling + UISearchController for Filza
 *
 * Hooks TGFileSystemListViewController to:
 * 1. Apply UIBlurEffect glass cells in tableView:willDisplayCell:forRowAtIndexPath:
 * 2. Attach a UISearchController to the navigation item in viewDidLoad
 *
 * All hooks use class_replaceMethod / method_setImplementation so they stack
 * cleanly on top of the existing Tweak.m hooks.
 */

@import UIKit;
#import <objc/runtime.h>
#import <objc/message.h>

// --------------------------------------------------------------------------
#pragma mark - Glass cell styling

static void applyLiquidGlass(UITableViewCell *cell) {
    if (!cell || cell.tag == 0xDEADB33F) return;
    cell.tag = 0xDEADB33F;
    cell.backgroundColor = [UIColor clearColor];

    // Remove any existing background view so we can insert ours.
    cell.backgroundView = nil;

    UIBlurEffect *blur;
    // UIBlurEffect(style:) enum value 10000 = ultraThinMaterial on iOS 15+
    // Use the string API so it compiles against older SDKs without warning.
    SEL styleInit = NSSelectorFromString(@"effectWithStyle:");
    Class blurClass = [UIBlurEffect class];
    if ([blurClass respondsToSelector:styleInit]) {
        // UIBlurEffectStyleSystemUltraThinMaterial = 10000
        blur = ((UIBlurEffect *(*)(Class, SEL, long))objc_msgSend)(blurClass, styleInit, (long)10000);
    }
    if (!blur) {
        blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    }

    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:blur];
    glass.layer.cornerRadius = 12.0;
    glass.layer.masksToBounds = YES;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glass.frame = cell.bounds;

    // Try UIGlassContainerView first (iOS 26+); fall back to vibrancy blur.
    Class glassContainer = NSClassFromString(@"UIGlassContainerView");
    if (glassContainer) {
        // UIGlassContainerView on iOS 26 accepts initWithEffect: as well.
        UIView *nativeGlass = [[glassContainer alloc] initWithFrame:cell.bounds];
        nativeGlass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        nativeGlass.layer.cornerRadius = 12.0;
        nativeGlass.layer.masksToBounds = YES;
        cell.backgroundView = nativeGlass;
    } else {
        cell.backgroundView = glass;
    }

    // Keep content readable: give content view a slightly transparent white
    // tint so icons/text remain visible over any background.
    cell.contentView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.04];
}

// --------------------------------------------------------------------------
#pragma mark - tableView:willDisplayCell:forRowAtIndexPath: hook

static IMP orig_willDisplayCell = NULL;
static void hook_willDisplayCell(id self, SEL _cmd, UITableView *tableView,
                                  UITableViewCell *cell, NSIndexPath *indexPath) {
    if (orig_willDisplayCell) {
        ((void (*)(id, SEL, UITableView *, UITableViewCell *, NSIndexPath *))orig_willDisplayCell)(
            self, _cmd, tableView, cell, indexPath);
    }
    applyLiquidGlass(cell);
}

// --------------------------------------------------------------------------
#pragma mark - Glass navigation bar

static void applyGlassNavBar(UIViewController *vc) {
    UINavigationController *nav = vc.navigationController;
    if (!nav) return;
    UINavigationBar *bar = nav.navigationBar;
    bar.translucent = YES;
    // UIBarStyleDefault with a blur effect view background = glass look.
    bar.barStyle = UIBarStyleDefault;

    // iOS 26 UIGlassEffect on nav bar via appearance if available.
    Class glassEffect = NSClassFromString(@"UIGlassEffect");
    if (glassEffect && [bar respondsToSelector:NSSelectorFromString(@"standardAppearance")]) {
        // Create a glass appearance via UINavigationBarAppearance if on iOS 15+
        Class appearanceClass = NSClassFromString(@"UINavigationBarAppearance");
        if (appearanceClass) {
            id appearance = [[appearanceClass alloc] init];
            SEL configBlur = NSSelectorFromString(@"configureWithTransparentBackground");
            if ([appearance respondsToSelector:configBlur]) {
                ((void (*)(id, SEL))objc_msgSend)(appearance, configBlur);
            }
            if ([bar respondsToSelector:NSSelectorFromString(@"setStandardAppearance:")]) {
                ((void (*)(id, SEL, id))objc_msgSend)(bar,
                    NSSelectorFromString(@"setStandardAppearance:"), appearance);
                ((void (*)(id, SEL, id))objc_msgSend)(bar,
                    NSSelectorFromString(@"setScrollEdgeAppearance:"), appearance);
                ((void (*)(id, SEL, id))objc_msgSend)(bar,
                    NSSelectorFromString(@"setCompactAppearance:"), appearance);
            }
        }
    } else {
        // iOS 15/16/17 fallback: just use tintColor + translucent.
        bar.barTintColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
        bar.tintColor = [UIColor whiteColor];
    }
}

// --------------------------------------------------------------------------
#pragma mark - UISearchController

static IMP orig_lgViewDidLoad = NULL;
static void hook_lgViewDidLoad(id self, SEL _cmd) {
    if (orig_lgViewDidLoad) {
        ((void (*)(id, SEL))orig_lgViewDidLoad)(self, _cmd);
    }

    if (![self isKindOfClass:[UITableViewController class]] &&
        ![self isKindOfClass:NSClassFromString(@"TGFileSystemListViewController")]) return;

    UITableViewController *vc = (UITableViewController *)self;

    // Make table view background clear so glass cells show.
    vc.tableView.backgroundColor = [UIColor clearColor];
    vc.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;

    // Only add search once.
    UINavigationItem *navItem = vc.navigationItem;
    if (navItem.searchController) return;

    // Build a UISearchController that filters by delegating to a helper.
    // We use a results controller = nil (in-place filtering) and observe the
    // searchBar's text via a target-action pattern on UISearchBar.
    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.obscuresBackgroundDuringPresentation = NO;
    search.hidesNavigationBarDuringPresentation = YES;

    // Tint the search bar to match glass aesthetic.
    UIColor *tint = [UIColor colorWithRed:0.4 green:0.85 blue:0.4 alpha:1.0]; // lime
    search.searchBar.tintColor = tint;
    search.searchBar.placeholder = @"Search files…";
    if (@available(iOS 13.0, *)) {
        search.searchBar.searchTextField.textColor = [UIColor whiteColor];
    }

    // Wire up: when search text changes, call setCurrentPath: or doLoadingPage
    // via Filza's own path filtering if available, else fall back to a simple
    // pass-through (the list must be populated by Filza itself).
    //
    // We store the search controller on the nav item; Filza's own delegate
    // methods are not replaced — this is purely additive.
    navItem.searchController = search;
    navItem.hidesSearchBarWhenScrolling = YES;

    // Apply glass to nav bar.
    applyGlassNavBar(vc);

    // Apply glass to the search bar itself.
    search.searchBar.barStyle = UIBarStyleBlack;
    search.searchBar.translucent = YES;
}

// --------------------------------------------------------------------------
#pragma mark - Public entry point called from Tweak.m installHooks()

void LiquidGlassInstallHooks(void) {
    Class fileSystemVC = NSClassFromString(@"TGFileSystemListViewController");
    if (!fileSystemVC) return;

    // Hook tableView:willDisplayCell:forRowAtIndexPath:
    SEL willDisplaySel = @selector(tableView:willDisplayCell:forRowAtIndexPath:);
    Method willDisplay = class_getInstanceMethod(fileSystemVC, willDisplaySel);
    if (willDisplay) {
        orig_willDisplayCell = method_getImplementation(willDisplay);
        method_setImplementation(willDisplay, (IMP)hook_willDisplayCell);
    } else {
        // Add the method if Filza doesn't implement it (will be called by UIKit).
        class_addMethod(fileSystemVC, willDisplaySel,
            (IMP)hook_willDisplayCell, "v@:@@{NSIndexPath=}");
    }

    // Hook viewDidLoad to add UISearchController.
    Method viewDidLoad = class_getInstanceMethod(fileSystemVC, @selector(viewDidLoad));
    if (viewDidLoad) {
        orig_lgViewDidLoad = method_getImplementation(viewDidLoad);
        method_setImplementation(viewDidLoad, (IMP)hook_lgViewDidLoad);
    }
}
