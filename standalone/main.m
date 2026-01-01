/**
 * Standalone Application - Native macOS app that displays Compose UI via IOSurface.
 *
 * Architecture Overview:
 * ----------------------
 * This app creates a shared GPU memory region (IOSurface) that the Compose UI
 * child process renders to. The child draws directly to this surface via Metal,
 * and we display it via CALayer - true zero-copy rendering.
 *
 * Components:
 * 1. IOSurface: Shared GPU memory created by iosurface_provider
 * 2. SurfaceView: NSView that displays IOSurface via CALayer.contents
 * 3. CVDisplayLink: Vsync-synchronized refresh of the layer
 * 4. Input Forwarding: Binary protocol over stdin pipe to child
 *
 * Resize Strategy (Double-Buffering):
 * -----------------------------------
 * Window resize is challenging because IOSurfaces cannot be resized in-place.
 * We use double-buffering to prevent flashing:
 *
 * 1. User starts resizing → we track the pending size
 * 2. Throttle timer fires (every 50ms during drag)
 * 3. Create NEW surface at pending size (old surface still displayed)
 * 4. Tell child to render to new surface
 * 5. After delay (33ms), swap: display new surface, release old
 * 6. Repeat while resize continues
 *
 * This ensures the old content remains visible until new content is ready.
 */
#import <Cocoa/Cocoa.h>
#import <IOSurface/IOSurface.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import "iosurface_provider.h"
#import "input_cocoa.h"

/// Convert NSEvent modifier flags to our protocol bitmask
static int getModifiers(NSEventModifierFlags flags) {
    int mods = 0;
    if (flags & NSEventModifierFlagShift) mods |= INPUT_MOD_SHIFT;
    if (flags & NSEventModifierFlagControl) mods |= INPUT_MOD_CTRL;
    if (flags & NSEventModifierFlagOption) mods |= INPUT_MOD_ALT;
    if (flags & NSEventModifierFlagCommand) mods |= INPUT_MOD_META;
    return mods;
}

/**
 * SurfaceView - Displays an IOSurface and handles input forwarding.
 *
 * This view:
 * - Uses layer-backing with IOSurface as contents (zero-copy display)
 * - Runs a CVDisplayLink for vsync-synchronized updates
 * - Captures all mouse/keyboard events and forwards them to the child process
 * - Implements double-buffered resize to prevent flashing
 *
 * Resize Flow:
 * 1. setFrameSize called → store pendingSize, start resize if not already running
 * 2. beginResize → create new surface, tell child to render, schedule swap
 * 3. commitSwap (after 33ms) → swap surfaces, check if more resizes pending
 * 4. If more pending → schedule another beginResize cycle
 */
@interface SurfaceView : NSView

/// Currently displayed surface (what the user sees)
@property (assign) IOSurfaceRef surface;

/// New surface being rendered to (not yet displayed)
@property (assign) IOSurfaceRef pendingSurface;

/// Size of the pending surface (target size during resize)
@property (assign) NSSize pendingSize;

/// Size of the currently displayed surface
@property (assign) NSSize lastCommittedSize;

/// Vsync-synchronized display refresh
@property (assign) CVDisplayLinkRef displayLink;

/// Timer for delayed swap after child renders
@property (strong) NSTimer *swapTimer;

@end

/// CVDisplayLink callback - triggers layer redraw on each vsync.
static CVReturn displayLinkCallback(CVDisplayLinkRef displayLink,
                                    const CVTimeStamp *now,
                                    const CVTimeStamp *outputTime,
                                    CVOptionFlags flagsIn,
                                    CVOptionFlags *flagsOut,
                                    void *context) {
    SurfaceView *view = (__bridge SurfaceView *)context;
    // Trigger layer update on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [view.layer setNeedsDisplay];
    });
    return kCVReturnSuccess;
}

@implementation SurfaceView

#pragma mark - Initialization

/**
 * Initialize the view with layer-backing and display link.
 */
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.lastCommittedSize = frame.size;
        self.pendingSize = frame.size;
        
        // Pin content to top-left, no stretching during resize
        self.layer.contentsGravity = kCAGravityTopLeft;
        
        // Create and start CVDisplayLink for vsync-synchronized updates
        CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
        CVDisplayLinkSetOutputCallback(_displayLink, displayLinkCallback, (__bridge void *)self);
        CVDisplayLinkStart(_displayLink);
    }
    return self;
}

- (void)dealloc {
    if (_displayLink) {
        CVDisplayLinkStop(_displayLink);
        CVDisplayLinkRelease(_displayLink);
    }
    [_swapTimer invalidate];
}

#pragma mark - Layer Display

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)wantsUpdateLayer {
    return YES;
}

/**
 * Update layer contents with the current surface.
 * Called on each vsync by the CVDisplayLink.
 */
- (void)updateLayer {
    self.layer.contents = (__bridge id)self.surface;
    // Display surface pixels 1:1 as points
    self.layer.contentsScale = 1.0;
    [self.layer setContentsChanged];
}

#pragma mark - Resize Handling

/// Swap pending surface after child has rendered
- (void)commitSwap {
    self.swapTimer = nil;
    
    if (self.pendingSurface) {
        self.surface = self.pendingSurface;
        self.pendingSurface = NULL;
        self.lastCommittedSize = self.pendingSize;
        [self.layer setNeedsDisplay];
    }
    
    // Continue if size changed during swap delay
    if (!NSEqualSizes(self.pendingSize, self.lastCommittedSize)) {
        [self beginResize];
    }
}

/// Create new surface and schedule swap after one frame
- (void)beginResize {
    int w = (int)self.pendingSize.width, h = (int)self.pendingSize.height;
    if (w <= 0 || h <= 0) return;
    
    [self.swapTimer invalidate];
    
    iosurface_ipc_resize_surface(w, h);
    self.pendingSurface = iosurface_ipc_get_surface();
    input_send_resize(w, h, iosurface_ipc_get_surface_id());
    
    // Swap after one frame (17ms) so child has time to render.
    // For truly fast resize, you'd need signal-based coordination where
    // the child signals "I rendered to the new surface" and the host
    // swaps immediately upon receiving that signal.
    self.swapTimer = [NSTimer timerWithTimeInterval:0.017
                                             target:self
                                           selector:@selector(commitSwap)
                                           userInfo:nil
                                            repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:self.swapTimer forMode:NSRunLoopCommonModes];
}

/// Handle window resize with delayed swap to avoid flicker
- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    
    if (!NSEqualSizes(newSize, self.lastCommittedSize) && newSize.width > 0 && newSize.height > 0) {
        self.pendingSize = newSize;
        if (!self.swapTimer) {
            [self beginResize];
        }
    }
}

#pragma mark - Mouse Events

- (void)mouseDown:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    input_send_mouse_button(loc.x, self.bounds.size.height - loc.y, INPUT_BUTTON_LEFT, 1, getModifiers(event.modifierFlags));
}

- (void)mouseUp:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    input_send_mouse_button(loc.x, self.bounds.size.height - loc.y, INPUT_BUTTON_LEFT, 0, getModifiers(event.modifierFlags));
}

- (void)rightMouseDown:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    input_send_mouse_button(loc.x, self.bounds.size.height - loc.y, INPUT_BUTTON_RIGHT, 1, getModifiers(event.modifierFlags));
}

- (void)rightMouseUp:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    input_send_mouse_button(loc.x, self.bounds.size.height - loc.y, INPUT_BUTTON_RIGHT, 0, getModifiers(event.modifierFlags));
}

- (void)otherMouseDown:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    input_send_mouse_button(loc.x, self.bounds.size.height - loc.y, INPUT_BUTTON_MIDDLE, 1, getModifiers(event.modifierFlags));
}

- (void)otherMouseUp:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    input_send_mouse_button(loc.x, self.bounds.size.height - loc.y, INPUT_BUTTON_MIDDLE, 0, getModifiers(event.modifierFlags));
}

- (void)mouseMoved:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    input_send_mouse_move(loc.x, self.bounds.size.height - loc.y, getModifiers(event.modifierFlags));
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    input_send_mouse_move(loc.x, self.bounds.size.height - loc.y, getModifiers(event.modifierFlags));
}

- (void)rightMouseDragged:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    input_send_mouse_move(loc.x, self.bounds.size.height - loc.y, getModifiers(event.modifierFlags));
}

- (void)otherMouseDragged:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    input_send_mouse_move(loc.x, self.bounds.size.height - loc.y, getModifiers(event.modifierFlags));
}

- (void)scrollWheel:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    input_send_mouse_scroll(loc.x, self.bounds.size.height - loc.y, event.scrollingDeltaX, event.scrollingDeltaY, getModifiers(event.modifierFlags));
}

#pragma mark - Keyboard Events

- (void)keyDown:(NSEvent *)event {
    NSString *chars = event.characters;
    uint32_t codepoint = (chars.length > 0) ? [chars characterAtIndex:0] : 0;
    input_send_key(event.keyCode, codepoint, 1, getModifiers(event.modifierFlags));
}

- (void)keyUp:(NSEvent *)event {
    NSString *chars = event.characters;
    uint32_t codepoint = (chars.length > 0) ? [chars characterAtIndex:0] : 0;
    input_send_key(event.keyCode, codepoint, 0, getModifiers(event.modifierFlags));
}

- (void)flagsChanged:(NSEvent *)event {
    // Modifier key state changed - could track individual modifiers if needed
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (strong) NSWindow *window;
@property (assign) IOSurfaceRef surface;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Create menu with Cmd+W and Cmd+Q
    NSMenu *menuBar = [[NSMenu alloc] init];
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [menuBar addItem:appMenuItem];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
    [appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    [appMenuItem setSubmenu:appMenu];
    [NSApp setMainMenu:menuBar];
    
    // Create window
    NSRect frame = NSMakeRect(100, 100, 800, 600);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:NSWindowStyleMaskTitled |
                                                        NSWindowStyleMaskClosable |
                                                        NSWindowStyleMaskResizable |
                                                        NSWindowStyleMaskMiniaturizable
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    
    // Create IOSurface at point dimensions.
    // The child process determines how to render (at what density).
    iosurface_ipc_create_surface(800, 600);
    self.surface = iosurface_ipc_get_surface();
    
    // Draw "Starting child process..." on dark background
    size_t width = IOSurfaceGetWidth(self.surface);
    size_t height = IOSurfaceGetHeight(self.surface);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    IOSurfaceLock(self.surface, 0, NULL);
    CGContextRef ctx = CGBitmapContextCreate(
        IOSurfaceGetBaseAddress(self.surface),
        width, height, 8, IOSurfaceGetBytesPerRow(self.surface),
        colorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little
    );
    // Dark gray background
    CGContextSetRGBFillColor(ctx, 0.2, 0.2, 0.2, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, 0, width, height));
    // White text centered
    CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
    NSString *msg = @"Starting child process...";
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:24],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    NSSize textSize = [msg sizeWithAttributes:attrs];
    NSPoint point = NSMakePoint((width - textSize.width) / 2, (height - textSize.height) / 2);
    NSGraphicsContext *nsCtx = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:nsCtx];
    [msg drawAtPoint:point withAttributes:attrs];
    [NSGraphicsContext restoreGraphicsState];
    CGContextRelease(ctx);
    CGColorSpaceRelease(colorSpace);
    IOSurfaceUnlock(self.surface, 0, NULL);
    
    // Create view backed by IOSurface
    SurfaceView *view = [[SurfaceView alloc] initWithFrame:[[self.window contentView] bounds]];
    // Don't auto-resize the view - IOSurface stays at fixed size
    view.autoresizingMask = 0;
    view.surface = self.surface;
    CFRetain(self.surface);  // View holds a reference for double-buffering
    
    [self.window setContentView:view];
    [self.window setTitle:@"CMP Embed"];
    [self.window setDelegate:self];
    [self.window makeKeyAndOrderFront:nil];
    
    // Force initial display
    [view.layer setNeedsDisplay];
    [view.layer displayIfNeeded];
    
    // Activate app and bring window to front
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    
    // Launch renderer as child process (inherits mach port)
    // Use the native distributable for direct child process launch
    // Get path relative to host executable: host/build/cmp-host.app/Contents/MacOS/cmp-host
    // CMP UI is at: ui/composeApp/build/compose/binaries/main/app/cmpui.app/Contents/MacOS/cmpui
    NSString *execPath = [[NSBundle mainBundle] executablePath];
    NSString *projectRoot = [[[[[[execPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    NSString *rendererApp = [projectRoot stringByAppendingPathComponent:@"ui/composeApp/build/compose/binaries/main/app/cmpui.app/Contents/MacOS/cmpui"];
    const char *args[] = { "--embed", NULL };
    iosurface_ipc_launch_child([rendererApp UTF8String], args, NULL);
}

// Exit app when window closes
- (void)windowWillClose:(NSNotification *)notification {
    iosurface_ipc_stop();
    [NSApp terminate:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    iosurface_ipc_stop();
}

@end

// Signal handler for Ctrl+C - ensures child process is terminated
static void signalHandler(int sig) {
    iosurface_ipc_stop();
    exit(0);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // Handle Ctrl+C to ensure child cleanup
        signal(SIGINT, signalHandler);
        signal(SIGTERM, signalHandler);
        
        NSApplication *app = [NSApplication sharedApplication];
        // Make app a regular app (shows in Dock, receives keyboard events)
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
