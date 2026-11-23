/* TimeSplitters 2 launcher, in the manner of the other native ports' launch windows (Homeworld's, Ghost Recon's):
 * the game's logo over its own Oblask Dam, a card for each renderer (native Metal, or Vulkan through MoltenVK), a
 * row of tiles (Graphics Options, Controls, Saves, Updates) and Quit / Play. Then the recompiled game
 * (Contents/MacOS/split2_recomp) starts in this process, so the app in the Dock is the game.
 *
 * Settings are remembered here and handed to the game as the toolkit's environment variables, which win over its
 * settings file (README: "Running a build of your own"): RECOMP_D3D8_BACKEND, RECOMP_RES_SCALE, RECOMP_WIDESCREEN,
 * RECOMP_ANISO, RECOMP_FPS_CAP, RECOMP_FRAME_INTERP, RECOMP_FPS_OVERLAY, RECOMP_FULLSCREEN, and for Keyboard & Mouse
 * a bindings file (RECOMP_INPUT_CONFIG) with mouse look (RECOMP_MOUSE_LOOK, RECOMP_MOUSE_SENSITIVITY).
 *
 * Art: <data>/art (or a copy in the app's Resources/art), made from the player's own disc by mac/make_art.sh: the
 * title screen's logo textures and frames the game drew. Nothing from the game is in this repository; without the
 * art the window writes the title in plain type.
 * Updates: install.sh gives the app an updater (Contents/MacOS/update) that rebuilds it from the branch it follows.
 * Development: TS2_LAUNCHER_SHOT=<png> renders the window to an image (TS2_LAUNCHER_HOVER=<code> lights an item,
 * TS2_LAUNCHER_PANEL=<0|1> opens Graphics Options or Controls, TS2_LAUNCHER_CARD=<0|1> picks a renderer). */
#import <Cocoa/Cocoa.h>
#include <unistd.h>

static NSColor *accent(void) { return [NSColor colorWithSRGBRed:0.47 green:0.70 blue:1.00 alpha:1]; }       /* the logo's blue 2 */
static NSColor *accent_dim(void) { return [NSColor colorWithSRGBRed:0.22 green:0.35 blue:0.62 alpha:1]; }
static NSColor *text_c(void) { return [NSColor colorWithSRGBRed:0.92 green:0.94 blue:0.98 alpha:1]; }      /* its silver */
static NSColor *dim(void) { return [NSColor colorWithSRGBRed:0.60 green:0.67 blue:0.78 alpha:1]; }
static NSColor *ink(CGFloat a) { return [NSColor colorWithSRGBRed:0.015 green:0.03 blue:0.07 alpha:a]; }
static NSFont *heading(CGFloat size) { return [NSFont fontWithName:@"AvenirNext-Bold" size:size] ?: [NSFont systemFontOfSize:size weight:NSFontWeightBold]; }
static NSFont *heavy(CGFloat size) { return [NSFont fontWithName:@"AvenirNext-Heavy" size:size] ?: heading(size); }
static NSFont *body(CGFloat size, BOOL bold)
{ return [NSFont fontWithName:bold ? @"AvenirNext-DemiBold" : @"AvenirNext-Medium" size:size] ?: [NSFont systemFontOfSize:size weight:bold ? NSFontWeightSemibold : NSFontWeightRegular]; }
static void on_main(dispatch_block_t b) { CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, b); CFRunLoopWakeUp(CFRunLoopGetMain()); }

// ---------------------------------------------------------------- settings
@interface TSRow : NSObject
@property NSString *title; @property NSArray<NSDictionary *> *choices; @property NSInteger index;
@property (copy) void (^activate)(void);            /* runs something instead of cycling (Saves, Updates, a panel) */
@property (copy) NSString *(^summary)(void);        /* shows a value worked out elsewhere */
@property BOOL wide;
@end
@implementation TSRow
- (id)value { return self.choices[self.index][@"value"]; }
@end

@interface TSPanel : NSObject
@property NSString *title, *footnote; @property NSArray<TSRow *> *rows;
@end
@implementation TSPanel @end

// ---------------------------------------------------------------- the view
enum { HIT_NONE = -1, HIT_PLAY = 100, HIT_QUIT = 101, HIT_BACK = 102, HIT_CARD = 200, HIT_TILE = 300, HIT_ROW = 400 };   /* + 10*k + 0 left / 1 value / 2 right */
enum { W = 960, H = 660 };

@interface TSLaunchView : NSView
@property NSArray<TSRow *> *tiles; @property NSArray<TSPanel *> *panels;
@property NSInteger card, hover, pressed, focus, open, rowFocus;   /* focus: -1 the cards, else a tile; open: a panel, or -1 */
@property NSImage *backdrop, *logo, *glow; @property NSArray<NSImage *> *shots; @property NSString *hint;
@property (copy) void (^onPlay)(void); @property (copy) void (^onQuit)(void); @property (copy) void (^onChange)(void);
@end

@implementation TSLaunchView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }
- (NSArray<TSRow *> *)rows { return self.open >= 0 ? self.panels[self.open].rows : @[]; }
- (NSRect)cardRect:(NSInteger)i { return NSMakeRect(60 + i * 436, 250, 404, 224); }
- (NSRect)tileRect:(NSInteger)k   /* a row under the cards (a wide tile counts twice) */
{
    NSInteger units = 0, at = 0, n = (NSInteger)self.tiles.count;
    for (NSInteger j = 0; j < n; j++) { if (j == k) at = units; units += self.tiles[j].wide ? 2 : 1; }
    CGFloat u = (840 - 16 * (units - 1)) / (CGFloat)units;
    return NSMakeRect(60 + at * (u + 16), 500, self.tiles[k].wide ? 2 * u + 16 : u, 66);
}
- (NSRect)arrow:(NSInteger)k right:(BOOL)right { NSRect r = [self tileRect:k]; return NSMakeRect(right ? NSMaxX(r) - 22 : r.origin.x + 1, r.origin.y + 26, 21, 34); }
- (NSRect)playRect { return NSMakeRect(W - 60 - 200, H - 68, 200, 46); }
- (NSRect)quitRect { return NSMakeRect(W - 60 - 200 - 20 - 150, H - 68, 150, 46); }
- (NSRect)panelRect { CGFloat h = 92 + 58 * (CGFloat)self.rows.count; return NSMakeRect(120, MAX(30, 494 - h), 720, h); }
- (NSRect)rowRect:(NSInteger)k { NSRect p = self.panelRect; return NSMakeRect(p.origin.x + 30, p.origin.y + 72 + 58 * k, p.size.width - 60, 50); }
- (NSRect)rowArrow:(NSInteger)k right:(BOOL)right { NSRect r = [self rowRect:k]; return NSMakeRect(right ? NSMaxX(r) - 34 : NSMaxX(r) - 330, r.origin.y + 3, 30, 30); }
- (NSRect)rowValue:(NSInteger)k { NSRect r = [self rowRect:k]; return NSMakeRect(NSMaxX(r) - 300, r.origin.y + 4, 262, 28); }
- (BOOL)rowCycles:(NSInteger)k { return self.rows[k].choices.count > 1; }
- (void)openPanel:(NSInteger)i { self.open = i; self.rowFocus = 0; self.hover = HIT_NONE; self.needsDisplay = YES; }
- (void)closePanel { self.open = -1; self.hover = HIT_NONE; self.needsDisplay = YES; }
- (NSInteger)hit:(NSPoint)p
{
    if (NSPointInRect(p, self.playRect)) return HIT_PLAY;
    if (NSPointInRect(p, self.quitRect)) return self.open >= 0 ? HIT_BACK : HIT_QUIT;
    if (self.open >= 0) {
        for (NSInteger k = 0; k < (NSInteger)self.rows.count; k++) {
            if (![self rowCycles:k]) continue;
            if (NSPointInRect(p, [self rowArrow:k right:NO])) return HIT_ROW + 10 * k;
            if (NSPointInRect(p, [self rowArrow:k right:YES])) return HIT_ROW + 10 * k + 2;
            if (NSPointInRect(p, [self rowRect:k])) return HIT_ROW + 10 * k + 1;
        }
        return NSPointInRect(p, self.panelRect) ? HIT_NONE : HIT_BACK;    /* a click outside the panel closes it */
    }
    for (NSInteger i = 0; i < 2; i++) if (NSPointInRect(p, [self cardRect:i])) return HIT_CARD + i;
    for (NSInteger k = 0; k < (NSInteger)self.tiles.count; k++) {
        if (!NSPointInRect(p, [self tileRect:k])) continue;
        if (self.tiles[k].activate) return HIT_TILE + 10 * k + 1;
        if (NSPointInRect(p, [self arrow:k right:NO])) return HIT_TILE + 10 * k;
        if (NSPointInRect(p, [self arrow:k right:YES])) return HIT_TILE + 10 * k + 2;
        return HIT_TILE + 10 * k + 1;
    }
    return HIT_NONE;
}
- (void)updateTrackingAreas
{
    for (NSTrackingArea *t in self.trackingAreas) [self removeTrackingArea:t];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseMoved:(NSEvent *)e { NSInteger h = [self hit:[self convertPoint:e.locationInWindow fromView:nil]]; if (h != self.hover) { self.hover = h; self.needsDisplay = YES; } }
- (void)mouseExited:(NSEvent *)e { self.hover = HIT_NONE; self.needsDisplay = YES; }
- (void)mouseDown:(NSEvent *)e
{
    NSInteger h = [self hit:[self convertPoint:e.locationInWindow fromView:nil]];
    if (h >= HIT_CARD && h < HIT_CARD + 2 && e.clickCount == 2) { self.card = h - HIT_CARD; if (self.onChange) self.onChange(); if (self.onPlay) self.onPlay(); return; }   /* double-click: play with that one */
    self.pressed = h; self.needsDisplay = YES;
}
- (void)mouseUp:(NSEvent *)e
{
    NSInteger h = [self hit:[self convertPoint:e.locationInWindow fromView:nil]], p = self.pressed; self.pressed = HIT_NONE; self.needsDisplay = YES;
    if (h != p || h == HIT_NONE) return;
    if (h == HIT_PLAY) { if (self.onPlay) self.onPlay(); return; }
    if (h == HIT_QUIT) { if (self.onQuit) self.onQuit(); return; }
    if (h == HIT_BACK) { [self closePanel]; return; }
    if (h >= HIT_ROW) { NSInteger k = (h - HIT_ROW) / 10; self.rowFocus = k; [self stepRow:k by:(h - HIT_ROW) % 10 == 0 ? -1 : 1]; return; }
    if (h >= HIT_CARD && h < HIT_CARD + 2) { self.card = h - HIT_CARD; self.focus = -1; self.needsDisplay = YES; if (self.onChange) self.onChange(); return; }
    NSInteger k = (h - HIT_TILE) / 10, part = (h - HIT_TILE) % 10; self.focus = k;
    [self step:k by:part == 0 ? -1 : 1];
}
- (void)step:(NSInteger)k by:(NSInteger)dir
{
    if (k < 0) { self.card = (self.card + 2 + dir) % 2; self.needsDisplay = YES; if (self.onChange) self.onChange(); return; }
    TSRow *t = self.tiles[k];
    if (t.activate) { t.activate(); self.needsDisplay = YES; return; }
    NSInteger n = (NSInteger)t.choices.count; t.index = (t.index + dir + n) % n;
    self.needsDisplay = YES; if (self.onChange) self.onChange();
}
- (void)stepRow:(NSInteger)k by:(NSInteger)dir
{
    TSRow *t = self.rows[k]; NSInteger n = (NSInteger)t.choices.count; if (n < 2) return;
    t.index = (t.index + dir + n) % n;
    self.needsDisplay = YES; if (self.onChange) self.onChange();
}
- (void)moveRowFocus:(NSInteger)dir
{
    NSInteger n = (NSInteger)self.rows.count;
    for (NSInteger i = 0; i < n; i++) { self.rowFocus = (self.rowFocus + dir + n) % n; if ([self rowCycles:self.rowFocus]) break; }
    self.needsDisplay = YES;
}
- (void)keyDown:(NSEvent *)e
{
    if (self.open >= 0) {
        switch (e.keyCode) {
        case 0x24: case 0x4c: case 0x35: [self closePanel]; return;                          /* Return, Escape: back */
        case 0x7b: [self stepRow:self.rowFocus by:-1]; return;
        case 0x7c: [self stepRow:self.rowFocus by:1]; return;
        case 0x7e: [self moveRowFocus:-1]; return;
        case 0x7d: case 0x30: [self moveRowFocus:1]; return;
        }
        [super keyDown:e]; return;
    }
    NSInteger n = (NSInteger)self.tiles.count;
    switch (e.keyCode) {
    case 0x24: case 0x4c: if (self.focus >= 0 && self.tiles[self.focus].activate) { [self step:self.focus by:1]; return; }   /* Return */
                          if (self.onPlay) self.onPlay(); return;
    case 0x35: if (self.onQuit) self.onQuit(); return;                                       /* Escape */
    case 0x7b: [self step:self.focus by:-1]; return;                                         /* left / right: the focused item */
    case 0x7c: [self step:self.focus by:1]; return;
    case 0x7e: self.focus = self.focus < 0 ? n - 1 : self.focus - 1; self.needsDisplay = YES; return;   /* up / down: cards, then each tile */
    case 0x7d: case 0x30: self.focus = self.focus + 1 >= n ? -1 : self.focus + 1; self.needsDisplay = YES; return;   /* also Tab */
    }
    [super keyDown:e];
}

static void draw_text(NSString *s, NSFont *f, NSColor *c, NSRect r, NSTextAlignment al, NSShadow *sh, CGFloat kern)
{
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.alignment = al; ps.lineBreakMode = NSLineBreakByTruncatingTail;
    NSMutableDictionary *a = [@{NSFontAttributeName: f, NSForegroundColorAttributeName: c, NSParagraphStyleAttributeName: ps, NSKernAttributeName: @(kern)} mutableCopy];
    if (sh) a[NSShadowAttributeName] = sh;
    [s drawInRect:r withAttributes:a];
}
static void brackets(NSRect r, CGFloat len, CGFloat w, NSColor *c)     /* corner marks */
{
    [c setStroke]; NSBezierPath *p = [NSBezierPath bezierPath]; p.lineWidth = w; p.lineCapStyle = NSLineCapStyleSquare;
    CGFloat x0 = r.origin.x, y0 = r.origin.y, x1 = NSMaxX(r), y1 = NSMaxY(r);
    [p moveToPoint:NSMakePoint(x0, y0 + len)]; [p lineToPoint:NSMakePoint(x0, y0)]; [p lineToPoint:NSMakePoint(x0 + len, y0)];
    [p moveToPoint:NSMakePoint(x1 - len, y0)]; [p lineToPoint:NSMakePoint(x1, y0)]; [p lineToPoint:NSMakePoint(x1, y0 + len)];
    [p moveToPoint:NSMakePoint(x1, y1 - len)]; [p lineToPoint:NSMakePoint(x1, y1)]; [p lineToPoint:NSMakePoint(x1 - len, y1)];
    [p moveToPoint:NSMakePoint(x0 + len, y1)]; [p lineToPoint:NSMakePoint(x0, y1)]; [p lineToPoint:NSMakePoint(x0, y1 - len)];
    [p stroke];
}
static void fill_over(NSRect r) { NSRectFillUsingOperation(r, NSCompositingOperationSourceOver); }
/* an image filling a rectangle, aspect kept (cropped); `keep` = the share of the image's height to use, from the top */
static void draw_cover(NSImage *img, NSRect r, CGFloat fraction, CGFloat keep, CGFloat focusX, CGFloat focusY)
{
    NSSize is = img.size; is.height *= keep;
    CGFloat sc = MAX(r.size.width / is.width, r.size.height / is.height), w = r.size.width / sc, h = r.size.height / sc;
    NSRect from = NSMakeRect((img.size.width - w) * focusX, img.size.height - h - (is.height - h) * focusY, w, h);   /* NSImage rows: bottom-up */
    [img drawInRect:r fromRect:from operation:NSCompositingOperationSourceOver fraction:fraction respectFlipped:YES hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
}
static NSRect fit_rect(NSImage *img, NSRect r)
{
    CGFloat sc = MIN(r.size.width / img.size.width, r.size.height / img.size.height), w = img.size.width * sc, h = img.size.height * sc;
    return NSMakeRect(NSMidX(r) - w / 2, NSMidY(r) - h / 2, w, h);
}
- (void)drawButton:(NSRect)r title:(NSString *)title code:(NSInteger)code primary:(BOOL)primary
{
    BOOL hot = self.hover == code, down = self.pressed == code;
    if (primary) {
        NSGradient *g = [[NSGradient alloc] initWithStartingColor:[accent() colorWithAlphaComponent:down ? 0.85 : hot ? 0.72 : 0.58] endingColor:[accent_dim() colorWithAlphaComponent:down ? 0.9 : 0.72]];
        [g drawInRect:r angle:90];
        NSShadow *glow = [NSShadow new]; glow.shadowColor = [accent() colorWithAlphaComponent:hot ? 0.9 : 0.55]; glow.shadowBlurRadius = hot ? 18 : 12; glow.shadowOffset = NSZeroSize;
        [NSGraphicsContext saveGraphicsState]; [glow set]; [accent() setStroke]; NSBezierPath *b = [NSBezierPath bezierPathWithRect:NSInsetRect(r, 0.5, 0.5)]; b.lineWidth = 1.2; [b stroke]; [NSGraphicsContext restoreGraphicsState];
    } else {
        [ink(down ? 0.95 : 0.78) setFill]; fill_over(r);
        [(hot ? accent() : accent_dim()) setStroke]; NSBezierPath *b = [NSBezierPath bezierPathWithRect:NSInsetRect(r, 0.5, 0.5)]; b.lineWidth = 1; [b stroke];
    }
    brackets(NSInsetRect(r, -4, -4), 9, 2, primary || hot ? accent() : accent_dim());
    NSShadow *sh = [NSShadow new]; sh.shadowColor = [NSColor colorWithWhite:0 alpha:0.8]; sh.shadowOffset = NSMakeSize(0, -1); sh.shadowBlurRadius = 2;
    NSFont *f = heading(primary ? 19 : 16);
    NSDictionary *at = @{NSFontAttributeName: f, NSForegroundColorAttributeName: primary || hot ? NSColor.whiteColor : text_c(), NSShadowAttributeName: sh, NSKernAttributeName: @5};
    NSSize sz = [title sizeWithAttributes:at];
    [title drawAtPoint:NSMakePoint(NSMidX(r) - sz.width / 2 + 2.5, round(NSMidY(r) - f.capHeight / 2 - (f.ascender - f.capHeight))) withAttributes:at];
}
- (void)drawCard:(NSInteger)i shadow:(NSShadow *)sh
{
    static NSString *kicker[] = {@"NATIVE RENDERER", @"THROUGH MOLTENVK"}, *name[] = {@"METAL", @"VULKAN"};
    static NSString *line[] = {@"Apple's own graphics API, no translation layer", @"The port's original path, translated to Metal"};
    NSRect r = [self cardRect:i]; BOOL sel = self.card == i, hot = self.hover == HIT_CARD + i, foc = sel && self.focus == -1 && self.open < 0;
    if (sel) {                                                           /* the chosen renderer: a glow behind its card */
        NSShadow *glow = [NSShadow new]; glow.shadowColor = [accent() colorWithAlphaComponent:0.55]; glow.shadowBlurRadius = 26; glow.shadowOffset = NSZeroSize;
        [NSGraphicsContext saveGraphicsState]; [glow set]; [NSColor.blackColor setFill]; NSRectFill(r); [NSGraphicsContext restoreGraphicsState];
    }
    [NSColor.blackColor setFill]; NSRectFill(r);
    NSImage *shot = i < (NSInteger)self.shots.count ? self.shots[i] : nil;
    if (shot.size.width > 16) draw_cover(shot, r, sel ? 1 : hot ? 0.85 : 0.6, i == 0 ? 0.95 : 0.78, 0.5, i == 0 ? 0.6 : 0.35);   /* the portal; the base above the HUD */
    NSGradient *foot = [[NSGradient alloc] initWithColorsAndLocations:[NSColor colorWithWhite:0 alpha:0], 0.0, [NSColor colorWithWhite:0 alpha:0.3], 0.42, ink(0.94), 1.0, nil];
    [foot drawInRect:r angle:90];
    if (!sel) { [ink(hot ? 0.16 : 0.32) setFill]; fill_over(r); }
    NSColor *tc = sel || hot ? NSColor.whiteColor : [text_c() colorWithAlphaComponent:0.82];
    draw_text(kicker[i], heading(11), sel || hot ? accent() : dim(), NSMakeRect(r.origin.x + 20, NSMaxY(r) - 100, 360, 16), NSTextAlignmentLeft, sh, 3.5);
    draw_text(name[i], heavy(38), tc, NSMakeRect(r.origin.x + 18, NSMaxY(r) - 84, 360, 50), NSTextAlignmentLeft, sh, 6);
    draw_text(line[i], body(13, NO), sel || hot ? text_c() : dim(), NSMakeRect(r.origin.x + 20, NSMaxY(r) - 32, 370, 20), NSTextAlignmentLeft, sh, 0.2);
    [(sel ? accent() : hot ? [accent() colorWithAlphaComponent:0.7] : [accent_dim() colorWithAlphaComponent:0.7]) setStroke];
    NSBezierPath *b = [NSBezierPath bezierPathWithRect:NSInsetRect(r, 0.5, 0.5)]; b.lineWidth = sel ? 1.5 : 1; [b stroke];
    if (sel) {
        brackets(NSInsetRect(r, -6, -6), foc ? 22 : 16, foc ? 3 : 2.5, accent());
        NSRect tag = NSMakeRect(NSMaxX(r) - 104, r.origin.y + 12, 92, 22);    /* "SELECTED", top right */
        [[accent() colorWithAlphaComponent:0.92] setFill]; fill_over(tag);
        draw_text(@"SELECTED", heading(10.5), ink(1), NSMakeRect(tag.origin.x, tag.origin.y + 4, tag.size.width, 16), NSTextAlignmentCenter, nil, 2.5);
    }
}
- (void)drawArrow:(NSRect)r right:(BOOL)right lit:(BOOL)lit
{
    NSBezierPath *p = [NSBezierPath bezierPath]; CGFloat x0 = NSMidX(r) - 4, x1 = NSMidX(r) + 4, y0 = NSMidY(r) - 7, y1 = NSMidY(r) + 7, ym = NSMidY(r);
    if (right) { [p moveToPoint:NSMakePoint(x0, y0)]; [p lineToPoint:NSMakePoint(x1, ym)]; [p lineToPoint:NSMakePoint(x0, y1)]; }
    else { [p moveToPoint:NSMakePoint(x1, y0)]; [p lineToPoint:NSMakePoint(x0, ym)]; [p lineToPoint:NSMakePoint(x1, y1)]; }
    p.lineWidth = 2; p.lineCapStyle = NSLineCapStyleRound; p.lineJoinStyle = NSLineJoinStyleRound;
    [(lit ? NSColor.whiteColor : accent()) setStroke]; [p stroke];
}
- (void)drawTile:(NSInteger)k shadow:(NSShadow *)sh
{
    TSRow *t = self.tiles[k]; NSRect r = [self tileRect:k]; NSDictionary *c = t.choices[t.index];
    BOOL hot = self.hover >= HIT_TILE + 10 * k && self.hover <= HIT_TILE + 10 * k + 2, foc = self.focus == k, special = [c[@"accent"] boolValue];
    [ink(hot ? 0.9 : 0.76) setFill]; fill_over(r);
    [((hot || foc) ? accent() : [accent_dim() colorWithAlphaComponent:0.8]) setStroke];
    NSBezierPath *b = [NSBezierPath bezierPathWithRect:NSInsetRect(r, 0.5, 0.5)]; b.lineWidth = 1; [b stroke];
    [((hot || foc) ? accent() : accent_dim()) setFill]; NSRectFill(NSMakeRect(r.origin.x, r.origin.y, r.size.width, 2));   /* a lit top edge */
    if (foc) brackets(NSInsetRect(r, -4, -4), 8, 2, accent());
    draw_text(t.title.uppercaseString, heading(10.5), (hot || foc) ? accent() : dim(), NSMakeRect(r.origin.x, r.origin.y + 11, r.size.width, 16), NSTextAlignmentCenter, nil, 3);
    NSColor *vc = special ? accent() : self.hover == HIT_TILE + 10 * k + 1 ? NSColor.whiteColor : text_c();
    draw_text(t.summary ? t.summary() : c[@"label"], body(15, YES), vc, NSMakeRect(r.origin.x + 17, r.origin.y + 34, r.size.width - 34, 24), NSTextAlignmentCenter, sh, 0.2);
    if (!t.activate && t.choices.count > 1) {
        [self drawArrow:[self arrow:k right:NO] right:NO lit:self.hover == HIT_TILE + 10 * k];
        [self drawArrow:[self arrow:k right:YES] right:YES lit:self.hover == HIT_TILE + 10 * k + 2];
    }
}
- (void)drawPanel:(NSShadow *)sh                        /* a group of settings over the window, a row each */
{
    TSPanel *pn = self.panels[self.open];
    [ink(0.66) setFill]; fill_over(NSMakeRect(0, 0, W, H - 92));
    NSRect p = self.panelRect;
    NSShadow *glow = [NSShadow new]; glow.shadowColor = [accent() colorWithAlphaComponent:0.35]; glow.shadowBlurRadius = 30; glow.shadowOffset = NSZeroSize;
    [NSGraphicsContext saveGraphicsState]; [glow set]; [ink(0.97) setFill]; NSRectFill(p); [NSGraphicsContext restoreGraphicsState];
    [accent_dim() setStroke]; NSBezierPath *bp = [NSBezierPath bezierPathWithRect:NSInsetRect(p, 0.5, 0.5)]; bp.lineWidth = 1; [bp stroke];
    brackets(NSInsetRect(p, -6, -6), 22, 3, accent());
    draw_text(pn.title, heading(20), accent(), NSMakeRect(p.origin.x, p.origin.y + 22, p.size.width, 28), NSTextAlignmentCenter, sh, 6);
    [[accent_dim() colorWithAlphaComponent:0.6] setFill]; fill_over(NSMakeRect(p.origin.x + 30, p.origin.y + 60, p.size.width - 60, 1));
    for (NSInteger k = 0; k < (NSInteger)self.rows.count; k++) {
        TSRow *t = self.rows[k]; NSRect r = [self rowRect:k]; NSDictionary *c = t.choices[t.index]; BOOL cycles = [self rowCycles:k];
        BOOL hot = cycles && self.hover >= HIT_ROW + 10 * k && self.hover <= HIT_ROW + 10 * k + 2, foc = cycles && self.rowFocus == k;
        if (foc || hot) { [[accent() colorWithAlphaComponent:foc ? 0.12 : 0.07] setFill]; fill_over(NSInsetRect(r, -10, -2));
                          if (foc) { [accent() setFill]; NSRectFill(NSMakeRect(r.origin.x - 10, r.origin.y - 2, 3, r.size.height + 4)); } }
        draw_text(t.title.uppercaseString, heading(15), foc || hot ? accent() : cycles ? text_c() : dim(), NSMakeRect(r.origin.x + 6, r.origin.y + 8, 300, 24), NSTextAlignmentLeft, sh, 3);
        if (cycles) {
            [self drawArrow:[self rowArrow:k right:NO] right:NO lit:self.hover == HIT_ROW + 10 * k];
            [self drawArrow:[self rowArrow:k right:YES] right:YES lit:self.hover == HIT_ROW + 10 * k + 2];
        }
        draw_text(t.summary ? t.summary() : c[@"label"], body(cycles ? 18 : 16, YES), self.hover == HIT_ROW + 10 * k + 1 ? NSColor.whiteColor : text_c(),
                  cycles ? [self rowValue:k] : NSMakeRect(NSMaxX(r) - 420, r.origin.y + 7, 414, 28), cycles ? NSTextAlignmentCenter : NSTextAlignmentRight, sh, 0.3);
        draw_text(c[@"note"] ?: @"", body(12, NO), dim(), NSMakeRect(r.origin.x + 6, r.origin.y + 31, r.size.width - 12, 18), NSTextAlignmentRight, nil, 0);
        if (k + 1 < (NSInteger)self.rows.count) { [[accent_dim() colorWithAlphaComponent:0.3] setFill]; fill_over(NSMakeRect(r.origin.x, NSMaxY(r) + 3, r.size.width, 1)); }
    }
    if (pn.footnote.length) draw_text(pn.footnote, body(11.5, NO), dim(), NSMakeRect(p.origin.x + 30, NSMaxY(p) - 26, p.size.width - 60, 18), NSTextAlignmentCenter, nil, 0);
}
- (NSString *)currentHint
{
    if (self.open >= 0) return @"←/→ change  ·  ↑/↓ move  ·  Return or Esc goes back";
    NSInteger k = -1;
    if (self.hover >= HIT_TILE && self.hover < HIT_ROW) k = (self.hover - HIT_TILE) / 10; else if (self.hover == HIT_NONE && self.focus >= 0) k = self.focus;
    if (k >= 0 && k < (NSInteger)self.tiles.count) { TSRow *t = self.tiles[k]; return t.choices[t.index][@"note"]; }
    if (self.hover == HIT_CARD) return @"Metal: drawn by the port's own Metal renderer, nothing in between. Double-click to play.";
    if (self.hover == HIT_CARD + 1) return @"Vulkan: drawn through MoltenVK, the path the port first shipped with. Double-click to play.";
    return self.hint;
}
- (void)drawRect:(NSRect)dirty
{
    NSRect b = self.bounds;
    NSShadow *sh = [NSShadow new]; sh.shadowColor = [NSColor colorWithWhite:0 alpha:0.85]; sh.shadowOffset = NSMakeSize(0, -1); sh.shadowBlurRadius = 3;
    [ink(1) setFill]; NSRectFill(b);
    if (self.backdrop.size.width > 16) {
        draw_cover(self.backdrop, NSMakeRect(0, 0, W, 470), 1, 0.84, 0.5, 0.2);   /* the dam, its caption at the foot left off */
        [ink(0.16) setFill]; fill_over(NSMakeRect(0, 0, W, 470));                  /* snow is bright: a little dark for the logo */
        NSGradient *down = [[NSGradient alloc] initWithColorsAndLocations:ink(0.45), 0.0, ink(0.08), 0.32, ink(0.5), 0.66, ink(1.0), 1.0, nil];
        [down drawInRect:NSMakeRect(0, 0, W, 470) angle:-90];
    }
    NSGradient *vig = [[NSGradient alloc] initWithColorsAndLocations:[NSColor colorWithWhite:0 alpha:0], 0.0, [NSColor colorWithWhite:0 alpha:0.55], 1.0, nil];
    [vig drawInRect:b relativeCenterPosition:NSMakePoint(0, 0.25)];
    /* the logo, its own glow beneath it */
    if (self.logo.size.width > 16) {
        NSRect lr = fit_rect(self.logo, NSMakeRect(230, 26, 500, 150));
        if (self.glow.size.width > 16) [self.glow drawInRect:NSInsetRect(lr, -2, -2) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:0.85 respectFlipped:YES hints:nil];
        NSShadow *halo = [NSShadow new]; halo.shadowColor = [accent() colorWithAlphaComponent:0.45]; halo.shadowOffset = NSZeroSize; halo.shadowBlurRadius = 24;
        [NSGraphicsContext saveGraphicsState]; [halo set];
        [self.logo drawInRect:lr fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
        [NSGraphicsContext restoreGraphicsState];
    } else draw_text(@"TIMESPLITTERS 2", heavy(60), text_c(), NSMakeRect(0, 70, W, 80), NSTextAlignmentCenter, sh, 8);
    draw_text(@"NATIVE FOR APPLE SILICON  ·  RECOMPILED FROM YOUR XBOX DISC", heading(11.5), accent(), NSMakeRect(0, 184, W, 18), NSTextAlignmentCenter, sh, 4);
    draw_text(@"CHOOSE YOUR RENDERER", heading(10.5), dim(), NSMakeRect(60, 226, 400, 16), NSTextAlignmentLeft, sh, 3.5);
    draw_text(@"1990 · SIBERIA · OBLASK DAM", heading(10.5), dim(), NSMakeRect(W - 460, 226, 400, 16), NSTextAlignmentRight, sh, 3.5);
    for (NSInteger i = 0; i < 2; i++) [self drawCard:i shadow:sh];
    NSInteger hov = self.hover, foc = self.focus; if (self.open >= 0) self.hover = self.focus = HIT_NONE;   /* under a panel: nothing lit */
    for (NSInteger k = 0; k < (NSInteger)self.tiles.count; k++) [self drawTile:k shadow:sh];
    self.hover = hov; self.focus = foc;
    [[accent_dim() colorWithAlphaComponent:0.5] setFill]; fill_over(NSMakeRect(60, H - 92, 840, 1));
    if (self.open >= 0) [self drawPanel:sh];
    NSString *hint = [self currentHint];
    if (hint.length) draw_text(hint, body(12.5, NO), dim(), NSMakeRect(60, H - 58, 410, 40), NSTextAlignmentLeft, sh, 0.2);
    [self drawButton:self.quitRect title:self.open >= 0 ? @"BACK" : @"QUIT" code:self.open >= 0 ? HIT_BACK : HIT_QUIT primary:NO];
    [self drawButton:self.playRect title:@"PLAY" code:HIT_PLAY primary:YES];
}
@end

// ---------------------------------------------------------------- updates (the other ports' updater)
enum { UPD_NONE, UPD_CHECKING, UPD_CURRENT, UPD_AVAILABLE, UPD_ERROR };
static NSString *short_commit(NSString *c) { return c.length > 7 ? [c substringToIndex:7] : (c ?: @""); }
static NSString *update_check(NSString *updater)     /* the newest commit of the branch on GitHub; nil if it can't be reached */
{
    NSTask *t = [NSTask new]; t.executableURL = [NSURL fileURLWithPath:@"/bin/bash"]; t.arguments = @[updater, @"--check"];
    NSPipe *p = [NSPipe pipe]; t.standardOutput = p; t.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![t launchAndReturnError:nil]) return nil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_global_queue(0, 0), ^{ if (t.running) [t terminate]; });
    NSData *d = [p.fileHandleForReading readDataToEndOfFile]; [t waitUntilExit];
    NSString *out = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return t.terminationStatus == 0 && out.length >= 40 ? [out substringToIndex:40] : nil;
}
static NSArray<NSDictionary *> *update_choice(int state, NSString *branch, NSString *built, NSString *latest)
{
    NSString *label = @"Unavailable", *note = @"This copy wasn't installed from the repository (mac/install.sh)"; BOOL lit = NO;
    switch (state) {
    case UPD_CHECKING: label = @"Checking…"; note = [NSString stringWithFormat:@"Asking GitHub for the newest %@", branch]; break;
    case UPD_CURRENT: label = @"Up to Date"; note = [NSString stringWithFormat:@"%@ %@ · click to check again", branch, short_commit(built)]; break;
    case UPD_AVAILABLE: label = @"Update Ready"; lit = YES; note = [NSString stringWithFormat:@"%@ → %@: click to install", short_commit(built), short_commit(latest)]; break;
    case UPD_ERROR: label = @"Can’t Check"; note = @"GitHub unreachable: click to retry"; break;
    }
    return @[@{@"value": @"", @"label": label, @"note": note, @"accent": @(lit)}];
}
static NSString *update_phase(NSString *line, NSString *branch)
{
    if ([line hasPrefix:@"== fetching"]) return @"Downloading the update from GitHub";
    if ([line hasPrefix:[NSString stringWithFormat:@"== %@:", branch]]) return [@"Got " stringByAppendingString:[line substringFromIndex:branch.length + 4]];
    if ([line hasPrefix:@"== recompiling"]) return @"Rebuilding from your game: translating it to native code (1 of 2)";
    if ([line hasPrefix:@"== building"]) return @"Installing the new app (2 of 2)";
    return nil;
}
@interface TSBlockTarget : NSObject
@property (copy) void (^fire)(void);
- (void)clicked:(id)b;
@end
@implementation TSBlockTarget
- (void)clicked:(id)b { (void)b; if (self.fire) self.fire(); }
@end
static BOOL update_run(NSWindow *parent, NSString *updater, NSString *branch, NSString *logPath)   /* modal progress; YES when rebuilt */
{
    NSPanel *pn = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 520, 170) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    pn.title = @"Updating";
    NSTextField *title = [NSTextField labelWithString:@"Updating to the newest version"]; title.font = [NSFont boldSystemFontOfSize:14]; title.frame = NSMakeRect(20, 128, 480, 22);
    NSTextField *status = [NSTextField wrappingLabelWithString:@"Starting…"]; status.frame = NSMakeRect(20, 64, 480, 56);
    NSProgressIndicator *spin = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 44, 480, 12)]; spin.indeterminate = YES; [spin startAnimation:nil];
    NSTextField *time = [NSTextField labelWithString:@"This takes a few minutes. Your saves and settings are kept."]; time.font = [NSFont systemFontOfSize:11]; time.textColor = NSColor.secondaryLabelColor; time.frame = NSMakeRect(20, 14, 370, 18);
    NSButton *btn = [NSButton buttonWithTitle:@"Close" target:nil action:nil]; btn.frame = NSMakeRect(400, 8, 100, 30); btn.hidden = YES;
    for (NSView *x in @[title, status, spin, time, btn]) [pn.contentView addSubview:x];
    if (parent) [pn setFrameOrigin:NSMakePoint(NSMidX(parent.frame) - 260, NSMidY(parent.frame) - 85)]; else [pn center];
    [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
    NSFileHandle *log = [NSFileHandle fileHandleForWritingAtPath:logPath];
    NSTask *t = [NSTask new]; t.executableURL = [NSURL fileURLWithPath:@"/bin/bash"]; t.arguments = @[updater];
    NSPipe *pipe = [NSPipe pipe]; t.standardOutput = pipe; t.standardError = pipe;
    NSMutableString *pending = [NSMutableString new], *tail = [NSMutableString new];
    pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
        NSData *d = h.availableData; if (!d.length) return;
        [log writeData:d];
        NSString *chunk = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
        @synchronized (pending) {
            [pending appendString:chunk]; NSRange nl;
            while ((nl = [pending rangeOfString:@"\n"]).location != NSNotFound) {
                NSString *line = [pending substringToIndex:nl.location]; [pending deleteCharactersInRange:NSMakeRange(0, nl.location + 1)];
                [tail appendFormat:@"%@\n", line]; if (tail.length > 600) [tail deleteCharactersInRange:NSMakeRange(0, tail.length - 600)];
                NSString *ph = update_phase(line, branch); if (ph) on_main(^{ status.stringValue = ph; });
            }
        }
    };
    __block BOOL ok = NO;
    __attribute__((objc_precise_lifetime)) TSBlockTarget *bt = [TSBlockTarget new];   /* a button's target is weak: kept here */
    bt.fire = ^{ [NSApp stopModal]; }; btn.target = bt; btn.action = @selector(clicked:);
    t.terminationHandler = ^(NSTask *task) {
        int code = task.terminationStatus;
        on_main(^{
            pipe.fileHandleForReading.readabilityHandler = nil; [log closeFile];
            [spin stopAnimation:nil]; spin.hidden = YES; btn.hidden = NO;
            if (code == 0) { ok = YES; title.stringValue = @"Updated"; status.stringValue = @"The new version is installed. The app restarts when you press Restart."; btn.title = @"Restart"; }
            else {
                NSString *last; @synchronized (pending) { last = [[tail componentsSeparatedByString:@"\n"] componentsJoinedByString:@" "]; }
                title.stringValue = @"The update didn't finish";
                status.stringValue = [NSString stringWithFormat:@"Nothing was changed if it stopped before installing. Details: %@  (%@)", logPath, last.length > 160 ? [last substringFromIndex:last.length - 160] : last];
                time.stringValue = @"";
            }
        });
    };
    if (![t launchAndReturnError:nil]) { [log closeFile]; return NO; }
    [pn makeKeyAndOrderFront:nil]; [NSApp runModalForWindow:pn]; [pn orderOut:nil];
    return ok;
}

// ---------------------------------------------------------------- the window
static NSInteger index_of(NSArray<NSDictionary *> *c, id v, NSInteger dflt)
{ for (NSUInteger k = 0; k < c.count; k++) if ([c[k][@"value"] isEqual:v]) return (NSInteger)k; return dflt; }
static NSImage *image_at(NSArray<NSString *> *dirs, NSString *name)
{
    for (NSString *d in dirs) { NSImage *i = [[NSImage alloc] initWithContentsOfFile:[d stringByAppendingPathComponent:name]]; if (i.size.width > 16) return i; }
    return nil;
}
static TSRow *row(NSString *title, NSArray<NSDictionary *> *choices, id current, NSInteger dflt)
{
    TSRow *r = [TSRow new]; r.title = title; r.choices = choices; r.index = index_of(choices, current, dflt); return r;
}
static TSRow *info(NSString *title, NSString *(^value)(void), NSString *note)
{
    TSRow *r = [TSRow new]; r.title = title; r.choices = @[@{@"value": @"", @"label": @"", @"note": note ?: @""}]; r.summary = value; return r;
}

/* Keyboard & Mouse: the left stick on WASD, the triggers on the mouse buttons, the right stick on the mouse (mouse
 * look). Every control keeps its pad source, so a controller still works beside it. */
static NSString *const kbm_json =
    @"{\n  \"version\": 1,\n  \"controllers\": [\n    {\n      \"port\": 1,\n      \"device\": \"gamepad:0\",\n      \"bindings\": {\n"
     "        \"lstick_up\": [\"pad:ly+\", \"key:W\"], \"lstick_down\": [\"pad:ly-\", \"key:S\"],\n"
     "        \"lstick_left\": [\"pad:lx-\", \"key:A\"], \"lstick_right\": [\"pad:lx+\", \"key:D\"],\n"
     "        \"rtrigger\": [\"pad:rt\", \"mouse:left\"], \"ltrigger\": [\"pad:lt\", \"mouse:right\"],\n"
     "        \"a\": [\"pad:a\", \"key:SPACE\"], \"b\": [\"pad:b\", \"key:C\", \"key:ESCAPE\"],\n"
     "        \"x\": [\"pad:x\", \"key:R\"], \"y\": [\"pad:y\", \"key:F\"],\n"
     "        \"white\": [\"pad:rshoulder\", \"key:Q\"], \"black\": [\"pad:lshoulder\", \"key:E\"],\n"
     "        \"lthumb\": [\"pad:lthumb\", \"key:LSHIFT\"], \"rthumb\": [\"pad:rthumb\", \"mouse:middle\", \"key:V\"],\n"
     "        \"start\": [\"pad:start\", \"key:RETURN\"], \"back\": [\"pad:back\", \"key:TAB\"],\n"
     "        \"dpad_up\": [\"pad:dpad_up\", \"key:UP\"], \"dpad_down\": [\"pad:dpad_down\", \"key:DOWN\"],\n"
     "        \"dpad_left\": [\"pad:dpad_left\", \"key:LEFT\"], \"dpad_right\": [\"pad:dpad_right\", \"key:RIGHT\"]\n"
     "      }\n    }\n  ]\n}\n";

@interface Launcher : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window; @property (strong) TSLaunchView *view;
@property (strong) TSRow *display, *resolution, *widescreen, *filtering, *framerate, *interp, *fps, *scheme, *mouse, *saves, *updates, *controls;
@property NSString *dataPath;
@end

@implementation Launcher
- (BOOL)kbm { return [self.scheme.value isEqual:@"kbm"]; }
- (void)applicationDidFinishLaunching:(NSNotification *)n
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d registerDefaults:@{@"renderer": @"vulkan", @"fullscreen": @NO, @"scale": @2, @"widescreen": @YES, @"aniso": @8, @"cap": @"adaptive",
                          @"interp": @0, @"fps": @NO, @"scheme": @"kbm", @"mouse": @80}];
    NSDictionary *infoPlist = NSBundle.mainBundle.infoDictionary;
    self.dataPath = [(infoPlist[@"TS2DataPath"] ?: @"~/Games/TimeSplitters2Native") stringByExpandingTildeInPath];
    NSArray *artDirs = @[[self.dataPath stringByAppendingPathComponent:@"art"], [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"art"] ?: @""];

    TSLaunchView *v = [[TSLaunchView alloc] initWithFrame:NSMakeRect(0, 0, W, H)]; self.view = v;
    v.hover = v.pressed = HIT_NONE; v.focus = -1; v.open = -1;
    v.card = [[d stringForKey:@"renderer"] isEqual:@"metal"] ? 0 : 1;
    v.backdrop = image_at(artDirs, @"backdrop.jpg");
    v.logo = image_at(artDirs, @"logo.png"); v.glow = image_at(artDirs, @"glow.png");
    NSImage *none = [NSImage new];
    v.shots = @[image_at(artDirs, @"card_metal.jpg") ?: none, image_at(artDirs, @"card_vulkan.jpg") ?: none];
    v.hint = @"←/→ choose a renderer · ↑/↓ settings · Return plays · Esc quits";

    /* Graphics Options */
    self.display = row(@"Display", @[@{@"value": @NO, @"label": @"Window", @"note": @"A window on the desktop; Alt-Return switches in the game"},
                                     @{@"value": @YES, @"label": @"Full Screen", @"note": @"The whole display, Dock and menu bar out of the way"}], @([d boolForKey:@"fullscreen"]), 0);
    NSMutableArray *res = [NSMutableArray array];
    for (int s = 1; s <= 4; s++)
        [res addObject:@{@"value": @(s), @"label": [NSString stringWithFormat:@"%dx  ·  %d × %d", s, 640 * s, 480 * s], @"short": [NSString stringWithFormat:@"%dx", s],
                         @"note": s == 1 ? @"The console's own 640 × 480: softest, lightest on the GPU" : s == 2 ? @"Sharp on a Retina display at little cost (recommended)"
                                : s == 3 ? @"Sharper still; for a larger window or full screen" : @"Supersampled: the cleanest edges, the most GPU work"}];
    self.resolution = row(@"Resolution", res, @([d integerForKey:@"scale"]), 1);
    self.widescreen = row(@"Widescreen", @[@{@"value": @YES, @"label": @"16:9", @"note": @"A wider camera, not a stretched one; menus and HUD laid out for it"},
                                           @{@"value": @NO, @"label": @"4:3", @"note": @"The picture as the console drew it"}], @([d boolForKey:@"widescreen"]), 0);
    self.filtering = row(@"Texture Filtering", @[@{@"value": @1, @"label": @"Console", @"short": @"Console Filtering", @"note": @"The game's own filtering"},
                                                 @{@"value": @4, @"label": @"4x Anisotropic", @"short": @"4x AF", @"note": @"Floors and walls stay sharp at an angle"},
                                                 @{@"value": @8, @"label": @"8x Anisotropic", @"short": @"8x AF", @"note": @"Floors and walls stay sharp at an angle"},
                                                 @{@"value": @16, @"label": @"16x Anisotropic", @"short": @"16x AF", @"note": @"The sharpest; costs a little GPU time"}], @([d integerForKey:@"aniso"]), 2);
    self.framerate = row(@"Frame Rate", @[@{@"value": @"adaptive", @"label": @"Adaptive", @"note": @"60 where the game ran at 60, paced the way the console paced it"},
                                          @{@"value": @"60", @"label": @"60 fps", @"note": @"Every frame at 60"},
                                          @{@"value": @"30", @"label": @"30 fps", @"note": @"Half the work: steadier on a busy or older Mac"}], [d stringForKey:@"cap"], 0);
    self.interp = row(@"Frame Interpolation", @[@{@"value": @0, @"label": @"Off", @"note": @"Each frame the game draws, shown once"},
                                                @{@"value": @2, @"label": @"2x", @"note": @"Twice the frames on screen while the game runs at 60: for 120 Hz displays"},
                                                @{@"value": @3, @"label": @"3x", @"note": @"Three frames for each the game draws"},
                                                @{@"value": @4, @"label": @"4x", @"note": @"Four frames for each the game draws"}], @([d integerForKey:@"interp"]), 0);
    self.fps = row(@"FPS Counter", @[@{@"value": @NO, @"label": @"Off", @"note": @"F9 shows it in the game"}, @{@"value": @YES, @"label": @"On", @"note": @"The frame rate in the corner; F9 hides it"}], @([d boolForKey:@"fps"]), 0);
    TSPanel *gp = [TSPanel new]; gp.title = @"GRAPHICS OPTIONS";
    gp.rows = @[self.display, self.resolution, self.widescreen, self.filtering, self.framerate, self.interp, self.fps];

    /* Controls */
    self.scheme = row(@"Scheme", @[@{@"value": @"kbm", @"label": @"Keyboard & Mouse", @"note": @"WASD and mouse look, with a controller still working beside them"},
                                   @{@"value": @"pad", @"label": @"Controller", @"note": @"Any pad macOS sees, as an Xbox controller; the keyboard as the toolkit maps it"}], [d stringForKey:@"scheme"], 0);
    NSMutableArray *ms = [NSMutableArray array];
    for (NSNumber *m in @[@40, @60, @80, @100]) [ms addObject:@{@"value": m, @"label": m.intValue == 80 ? @"80 (default)" : m.stringValue, @"note": @"How far the view turns for the mouse's travel"}];
    self.mouse = row(@"Mouse Speed", ms, @([d integerForKey:@"mouse"]), 2);
    __weak Launcher *wl = self;
    TSRow *move = info(@"Move · Look", ^{ return wl.kbm ? @"W A S D  ·  Mouse" : @"Left Stick  ·  Right Stick"; }, nil);
    TSRow *fire = info(@"Fire · Secondary", ^{ return wl.kbm ? @"Left Click  ·  Right Click" : @"Right Trigger  ·  Left Trigger"; }, nil);
    TSRow *abxy = info(@"A · B · X · Y", ^{ return wl.kbm ? @"Space  ·  C  ·  R  ·  F" : @"Pad  (keyboard: Z · X · A · S)"; }, nil);
    TSRow *wb = info(@"White · Black · Sticks", ^{ return wl.kbm ? @"Q  ·  E  ·  Shift / V" : @"Shoulders  ·  Stick Clicks"; }, nil);
    TSRow *menus = info(@"Start · Back · Menus", ^{ return wl.kbm ? @"Return  ·  Tab  ·  Arrows" : @"Start  ·  Back  ·  D-Pad"; }, nil);
    TSPanel *cp = [TSPanel new]; cp.title = @"CONTROLS"; cp.rows = @[self.scheme, self.mouse, move, fire, abxy, wb, menus];
    cp.footnote = @"In the game: F9 frame rate · F10 frame cap · F11 screenshot · Alt-Return full screen";
    v.panels = @[gp, cp];

    TSRow *gfx = [TSRow new]; gfx.title = @"Graphics Options"; gfx.wide = YES;
    gfx.choices = @[@{@"value": @"", @"label": @"", @"note": @"Display, resolution, widescreen, filtering, frame rate, interpolation"}];
    gfx.summary = ^NSString * {
        Launcher *l = wl; NSMutableArray *a = [NSMutableArray array];
        for (TSRow *t in @[l.display, l.resolution, l.widescreen, l.filtering]) [a addObject:t.choices[t.index][@"short"] ?: t.choices[t.index][@"label"]];
        return [a componentsJoinedByString:@"  ·  "];
    };
    __weak TSLaunchView *wv = v; gfx.activate = ^{ [wv openPanel:0]; };
    self.controls = [TSRow new]; self.controls.title = @"Controls";
    self.controls.choices = @[@{@"value": @"", @"label": @"", @"note": @"Keyboard & Mouse or a controller, and which key does what"}];
    self.controls.summary = ^NSString * { return wl.kbm ? @"Keys & Mouse" : @"Controller"; };
    self.controls.activate = ^{ [wv openPanel:1]; };
    NSString *saves = [self.dataPath stringByAppendingPathComponent:@"game/UDATA/4553000a"];
    self.saves = [TSRow new]; self.saves.title = @"Saves";
    self.saves.choices = @[@{@"value": @"", @"label": @"Open", @"note": [@"Your profiles and story progress: " stringByAppendingString:[saves stringByAbbreviatingWithTildeInPath]]}];
    self.saves.activate = ^{ [[NSFileManager defaultManager] createDirectoryAtPath:saves withIntermediateDirectories:YES attributes:nil error:nil];
                             [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:saves isDirectory:YES]]; };
    [self setupUpdates];
    v.tiles = @[gfx, self.controls, self.saves, self.updates];
    __weak Launcher *ws = self;
    v.onPlay = ^{ [ws play]; };
    v.onQuit = ^{ [NSApp terminate:nil]; };
    v.onChange = ^{ [ws save]; };

    const char *shot = getenv("TS2_LAUNCHER_SHOT");
    if (shot) {                                                          /* development: the window as an image */
        if (getenv("TS2_LAUNCHER_HOVER")) v.hover = atoi(getenv("TS2_LAUNCHER_HOVER"));
        if (getenv("TS2_LAUNCHER_CARD")) v.card = atoi(getenv("TS2_LAUNCHER_CARD"));
        if (getenv("TS2_LAUNCHER_PANEL")) v.open = atoi(getenv("TS2_LAUNCHER_PANEL"));
        NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds]; [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(shot) atomically:YES];
        exit(0);
    }
    NSWindow *w = [[NSWindow alloc] initWithContentRect:v.frame styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskFullSizeContentView
                                                backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO; w.titlebarAppearsTransparent = YES; w.titleVisibility = NSWindowTitleHidden; w.movableByWindowBackground = YES;
    w.title = @"TimeSplitters 2"; w.backgroundColor = NSColor.blackColor; w.contentView = v;
    self.window = w; [w center]; [w makeKeyAndOrderFront:nil]; [w makeFirstResponder:v];
    [NSApp activateIgnoringOtherApps:YES];
    if (getenv("TS2_LAUNCHER_PLAY")) dispatch_async(dispatch_get_main_queue(), ^{ [ws play]; });   /* development: Play at once */
}
- (void)setupUpdates
{
    NSDictionary *infoPlist = NSBundle.mainBundle.infoDictionary;
    NSString *updater = [NSBundle.mainBundle.executablePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"update"];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:updater]) updater = nil;
    NSString *branch = infoPlist[@"TS2Branch"] ?: @"mac-local", *built = infoPlist[@"TS2Built"] ?: @"";
    TSRow *u = [TSRow new]; u.title = @"Updates"; self.updates = u;
    __block int state = updater ? UPD_CHECKING : UPD_NONE; __block NSString *latest = nil;
    u.choices = update_choice(state, branch, built, nil);
    __weak TSRow *wu = u; __weak Launcher *ws = self;
    void (^check)(void) = ^{
        if (!updater) return;
        state = UPD_CHECKING; wu.choices = update_choice(state, branch, built, nil); ws.view.needsDisplay = YES;
        void (^done)(NSString *) = ^(NSString *l) {
            latest = l; state = !l ? UPD_ERROR : [l isEqualToString:built] ? UPD_CURRENT : UPD_AVAILABLE;
            wu.choices = update_choice(state, branch, built, l); ws.view.needsDisplay = YES;
        };
        if (getenv("TS2_LAUNCHER_SHOT")) { done(update_check(updater)); return; }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ NSString *l = update_check(updater); on_main(^{ done(l); }); });
    };
    check();
    u.activate = ^{
        if (state == UPD_CHECKING || state == UPD_NONE) return;
        if (state != UPD_AVAILABLE) { check(); return; }
        NSAlert *a = [NSAlert new];
        a.messageText = @"Update to the newest version?";
        a.informativeText = [NSString stringWithFormat:@"The %@ branch (%@) is downloaded from GitHub and the app is rebuilt from your own copy of the game, "
                             "which takes a few minutes. Your saves and settings are kept. The app restarts when it is done.", branch, short_commit(latest)];
        [a addButtonWithTitle:@"Update"]; [a addButtonWithTitle:@"Cancel"];
        if ([a runModal] != NSAlertFirstButtonReturn) return;
        if (update_run(ws.window, updater, branch, [ws.dataPath stringByAppendingPathComponent:@"update.log"])) {
            NSTask *o = [NSTask new]; o.executableURL = [NSURL fileURLWithPath:@"/usr/bin/open"]; o.arguments = @[@"-n", NSBundle.mainBundle.bundlePath];
            [o launchAndReturnError:nil]; [o waitUntilExit];
            exit(0);
        }
        check();
    };
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)a { return YES; }
- (void)save
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:self.view.card == 0 ? @"metal" : @"vulkan" forKey:@"renderer"];
    [d setBool:[self.display.value boolValue] forKey:@"fullscreen"];
    [d setInteger:[self.resolution.value integerValue] forKey:@"scale"];
    [d setBool:[self.widescreen.value boolValue] forKey:@"widescreen"];
    [d setInteger:[self.filtering.value integerValue] forKey:@"aniso"];
    [d setObject:self.framerate.value forKey:@"cap"];
    [d setInteger:[self.interp.value integerValue] forKey:@"interp"];
    [d setBool:[self.fps.value boolValue] forKey:@"fps"];
    [d setObject:self.scheme.value forKey:@"scheme"];
    [d setInteger:[self.mouse.value integerValue] forKey:@"mouse"];
    [d synchronize];
}
- (void)play
{
    [self save];
    NSString *game = [self.dataPath stringByAppendingPathComponent:@"game"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:[game stringByAppendingPathComponent:@"default.xbe"]]) {
        NSAlert *a = [NSAlert new]; a.messageText = @"The game files are missing";
        a.informativeText = [NSString stringWithFormat:@"Expected your disc's files in %@ (default.xbe and the rest).", [game stringByAbbreviatingWithTildeInPath]];
        [a runModal]; return;
    }
    setenv("RECOMP_GAME_DIR", game.fileSystemRepresentation, 1);
    setenv("RECOMP_D3D8_BACKEND", self.view.card == 0 ? "metal" : "vulkan", 1);
    setenv("RECOMP_FULLSCREEN", [self.display.value boolValue] ? "1" : "0", 1);
    setenv("RECOMP_RES_SCALE", [[self.resolution.value stringValue] UTF8String], 1);
    setenv("RECOMP_WIDESCREEN", [self.widescreen.value boolValue] ? "1" : "0", 1);
    setenv("RECOMP_ANISO", [[self.filtering.value stringValue] UTF8String], 1);
    setenv("RECOMP_FPS_CAP", [self.framerate.value UTF8String], 1);
    setenv("RECOMP_FRAME_INTERP", [[self.interp.value stringValue] UTF8String], 1);
    setenv("RECOMP_FPS_OVERLAY", [self.fps.value boolValue] ? "1" : "0", 1);
    if (self.kbm) {
        NSString *path = [self.dataPath stringByAppendingPathComponent:@"keyboard_mouse.json"];
        [kbm_json writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        setenv("RECOMP_INPUT_CONFIG", path.fileSystemRepresentation, 1);
        setenv("RECOMP_MOUSE_LOOK", "1", 1);
        setenv("RECOMP_MOUSE_SENSITIVITY", [[self.mouse.value stringValue] UTF8String], 1);
    } else {
        unsetenv("RECOMP_INPUT_CONFIG"); unsetenv("RECOMP_MOUSE_LOOK"); unsetenv("RECOMP_MOUSE_SENSITIVITY");   /* the player's own bindings */
    }
    [self.window orderOut:nil];
    NSString *exe = [NSBundle.mainBundle.executablePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"split2_recomp"];
    char *const av[] = {(char *)exe.fileSystemRepresentation, NULL};
    execv(av[0], av);
    NSAlert *a = [NSAlert new]; a.messageText = @"The game did not start"; a.informativeText = exe; [a runModal];
    [self.window makeKeyAndOrderFront:nil];
}
@end

int main(int argc, const char **argv)
{
    (void)argc; (void)argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        Launcher *l = [Launcher new]; app.delegate = l;
        [app run];
    }
    return 0;
}
