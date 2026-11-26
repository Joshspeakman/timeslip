/* Timeslip's launcher, in the manner of the other native ports' launch windows (Homeworld's, Ghost Recon's): a card
 * for each game of the collection (TimeSplitters 2, Future Perfect) under the chosen one's logo, backdrop and place,
 * with the project's name, TIMESLIP, as its subtitle; a row of tiles (Graphics Options, Controls, Play Together, Saves,
 * Updates) for the chosen game; and Quit / Play. Then that game's recompiled executable (Contents/MacOS/timeslip or
 * timeslip_fp) starts in this process, so the app in the Dock is the game. Laid out as the Windows launcher is
 * (recompose's launcher_showcase.inc with this repository's src/launcher_games.c): the same cards, words and panels.
 *
 * Settings: graphics, the renderer and the mouse are read from and written to the game's settings file,
 * titles/<ID>.conf, which its in-game menu (Esc) changes too, so the two always agree; what the game's launcher kept
 * in its own settings domain before is carried into the file the first time. System Link and online co-op are chosen
 * for each start and handed over as the toolkit's environment variables (RECOMP_SYSLINK, RECOMP_LOCKSTEP_NET, ...).
 * Each game keeps the data folder and settings domain it had as an app of its own.
 *
 * Art: <data>/art (or a copy in the app's Resources/art_<game>), made from the player's own disc by mac/make_art.sh:
 * the title screen's logo textures and frames the game drew. Nothing from the games is in this repository; without
 * the art the window writes the game's name in plain type.
 * Updates: install.sh gives the app an updater (Contents/MacOS/update, mac/update.sh) that rebuilds it from the newest
 * GitHub release.
 * Development: mac/README.md ("Development"): TS2_LAUNCHER_SHOT, _GAME, _PANEL, _ROWFOCUS, _HOVER, _PLAY;
 * TS2_CONF_DIR, TS2_LAUNCHER_PREFS and TS2_DATA_PATH_<TS2|FP> keep a test off the player's own settings and games. */
#import <Cocoa/Cocoa.h>
#include <unistd.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/if.h>

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
@property NSString *linkTitle; @property NSInteger linkPanel; @property BOOL linkLeft;   /* a button in its title bar opening another panel */
@end
@implementation TSPanel @end

// ---------------------------------------------------------------- the view
enum { HIT_NONE = -1, HIT_PLAY = 100, HIT_QUIT = 101, HIT_BACK = 102, HIT_PLINK = 103, HIT_CARD = 200, HIT_TILE = 300, HIT_ROW = 400 };   /* + 10*k + 0 left / 1 value / 2 right */
enum { W = 960, H = 660 };

@interface TSLaunchView : NSView
@property NSArray<TSRow *> *tiles; @property NSArray<TSPanel *> *panels;
@property NSInteger card, hover, pressed, focus, open, rowFocus;   /* focus: -1 the cards, else a tile; open: a panel, or -1; rowFocus -1: the panel's link */
@property NSImage *backdrop, *logo, *glow; @property NSString *hint;
/* the games, a card each: name, line, image, ready (NO: not installed, dimmed and not chosen) */
@property NSArray<NSDictionary *> *cards;
@property NSString *titleText, *place;   /* the chosen game's name without its logo art; where its backdrop is */
@property (copy) void (^onPlay)(void); @property (copy) void (^onQuit)(void); @property (copy) void (^onChange)(void);
@property (copy) void (^onSelect)(NSInteger game);
@end

@implementation TSLaunchView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }
- (NSArray<TSRow *> *)rows { return self.open >= 0 ? self.panels[self.open].rows : @[]; }
- (NSRect)cardRect:(NSInteger)i { return NSMakeRect(i == 0 ? 60 : 496, 250, 404, 224); }   /* a card for each game */
- (BOOL)cardReady:(NSInteger)i { return i >= 0 && i < (NSInteger)self.cards.count && [self.cards[i][@"ready"] boolValue]; }
- (NSRect)linkRect { NSRect p = self.panelRect; TSPanel *pn = self.panels[self.open];
                     return pn.linkLeft ? NSMakeRect(p.origin.x + 24, p.origin.y + 21, 120, 28) : NSMakeRect(NSMaxX(p) - 24 - 132, p.origin.y + 21, 132, 28); }
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
- (CGFloat)rowPitch { return self.rows.count > 7 ? 55 : 58; }   /* eight rows still clear the buttons */
- (NSRect)panelRect { CGFloat h = 92 + self.rowPitch * (CGFloat)self.rows.count; return NSMakeRect(120, MAX(30, 494 - h), 720, h); }
- (NSRect)rowRect:(NSInteger)k { NSRect p = self.panelRect; return NSMakeRect(p.origin.x + 30, p.origin.y + 72 + self.rowPitch * k, p.size.width - 60, 50); }
- (NSRect)rowArrow:(NSInteger)k right:(BOOL)right { NSRect r = [self rowRect:k]; return NSMakeRect(right ? NSMaxX(r) - 34 : NSMaxX(r) - 330, r.origin.y + 3, 30, 30); }
- (NSRect)rowValue:(NSInteger)k { NSRect r = [self rowRect:k]; return NSMakeRect(NSMaxX(r) - 300, r.origin.y + 4, 262, 28); }
- (BOOL)rowCycles:(NSInteger)k { return self.rows[k].choices.count > 1 || self.rows[k].activate != nil; }   /* cycles, or runs something */
- (void)openPanel:(NSInteger)i
{
    self.open = i; self.hover = HIT_NONE; self.rowFocus = 0;
    while (self.rowFocus < (NSInteger)self.rows.count - 1 && ![self rowCycles:self.rowFocus]) self.rowFocus++;
    self.needsDisplay = YES;
}
- (void)selectCard:(NSInteger)i { if (![self cardReady:i] || i == self.card) return; if (self.onSelect) self.onSelect(i); self.needsDisplay = YES; }
- (void)closePanel { self.open = -1; self.hover = HIT_NONE; self.needsDisplay = YES; }
- (NSInteger)hit:(NSPoint)p
{
    if (NSPointInRect(p, self.playRect)) return HIT_PLAY;
    if (NSPointInRect(p, self.quitRect)) return self.open >= 0 ? HIT_BACK : HIT_QUIT;
    if (self.open >= 0) {
        if (self.panels[self.open].linkTitle && NSPointInRect(p, self.linkRect)) return HIT_PLINK;
        for (NSInteger k = 0; k < (NSInteger)self.rows.count; k++) {
            if (![self rowCycles:k]) continue;
            if (NSPointInRect(p, [self rowArrow:k right:NO])) return HIT_ROW + 10 * k;
            if (NSPointInRect(p, [self rowArrow:k right:YES])) return HIT_ROW + 10 * k + 2;
            if (NSPointInRect(p, [self rowRect:k])) return HIT_ROW + 10 * k + 1;
        }
        return NSPointInRect(p, self.panelRect) ? HIT_NONE : HIT_BACK;    /* a click outside the panel closes it */
    }
    for (NSInteger i = 0; i < (NSInteger)self.cards.count; i++) if (NSPointInRect(p, [self cardRect:i])) return HIT_CARD + i;
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
    if (h >= HIT_CARD && h < HIT_TILE && e.clickCount == 2 && [self cardReady:h - HIT_CARD]) {   /* double-click: play that game */
        [self selectCard:h - HIT_CARD]; if (self.onPlay) self.onPlay(); return;
    }
    self.pressed = h; self.needsDisplay = YES;
}
- (void)mouseUp:(NSEvent *)e
{
    NSInteger h = [self hit:[self convertPoint:e.locationInWindow fromView:nil]], p = self.pressed; self.pressed = HIT_NONE; self.needsDisplay = YES;
    if (h != p || h == HIT_NONE) return;
    if (h == HIT_PLAY) { if (self.onPlay) self.onPlay(); return; }
    if (h == HIT_QUIT) { if (self.onQuit) self.onQuit(); return; }
    if (h == HIT_BACK) { [self closePanel]; return; }
    if (h == HIT_PLINK) { [self openPanel:self.panels[self.open].linkPanel]; return; }
    if (h >= HIT_ROW) { NSInteger k = (h - HIT_ROW) / 10; self.rowFocus = k; [self stepRow:k by:(h - HIT_ROW) % 10 == 0 ? -1 : 1]; return; }
    if (h >= HIT_CARD && h < HIT_TILE) { self.focus = -1; [self selectCard:h - HIT_CARD]; self.needsDisplay = YES; return; }
    NSInteger k = (h - HIT_TILE) / 10, part = (h - HIT_TILE) % 10; self.focus = k;
    [self step:k by:part == 0 ? -1 : 1];
}
- (void)step:(NSInteger)k by:(NSInteger)dir
{
    if (k < 0) {                                                        /* the cards: the next game that is installed */
        NSInteger n = (NSInteger)self.cards.count;
        for (NSInteger j = 1; j < n; j++) { NSInteger c = ((self.card + dir * j) % n + n) % n; if ([self cardReady:c]) { [self selectCard:c]; break; } }
        return;
    }
    TSRow *t = self.tiles[k];
    if (t.activate) { t.activate(); self.needsDisplay = YES; return; }
    NSInteger n = (NSInteger)t.choices.count; t.index = (t.index + dir + n) % n;
    self.needsDisplay = YES; if (self.onChange) self.onChange();
}
- (void)stepRow:(NSInteger)k by:(NSInteger)dir
{
    TSRow *t = self.rows[k]; NSInteger n = (NSInteger)t.choices.count;
    if (t.activate) { t.activate(); self.needsDisplay = YES; return; }       /* e.g. typing the host's address */
    if (n < 2) return;
    t.index = (t.index + dir + n) % n;
    self.needsDisplay = YES; if (self.onChange) self.onChange();
}
- (void)moveRowFocus:(NSInteger)dir
{
    NSInteger n = (NSInteger)self.rows.count, first = 0;
    while (first < n - 1 && ![self rowCycles:first]) first++;
    if (self.panels[self.open].linkTitle) {                             /* up from the first row: the title bar's button */
        if (self.rowFocus == -1) { if (dir > 0) self.rowFocus = first; self.needsDisplay = YES; return; }
        if (dir < 0 && self.rowFocus == first) { self.rowFocus = -1; self.needsDisplay = YES; return; }
    }
    for (NSInteger i = 0; i < n; i++) { self.rowFocus = (self.rowFocus + dir + n) % n; if ([self rowCycles:self.rowFocus]) break; }
    self.needsDisplay = YES;
}
- (void)keyDown:(NSEvent *)e
{
    if (self.open >= 0) {
        switch (e.keyCode) {
        case 0x24: case 0x4c: case 0x31: case 0x7b: case 0x7c:                              /* on the title bar's button: press it */
            if (self.rowFocus == -1) { [self openPanel:self.panels[self.open].linkPanel]; return; }
            if (e.keyCode == 0x7b) { [self stepRow:self.rowFocus by:-1]; return; }
            if (e.keyCode == 0x7c) { [self stepRow:self.rowFocus by:1]; return; }
            if (e.keyCode == 0x31) break;
            [self closePanel]; return;                                                      /* Return: back */
        case 0x35: [self closePanel]; return;                                               /* Escape: back */
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
    NSDictionary *cd = self.cards[i]; BOOL ready = [cd[@"ready"] boolValue];
    NSRect r = [self cardRect:i]; BOOL sel = self.card == i, hot = ready && self.hover == HIT_CARD + i, foc = sel && self.focus == -1 && self.open < 0;
    if (sel) {                                                           /* the chosen game: a glow behind its card */
        NSShadow *glow = [NSShadow new]; glow.shadowColor = [accent() colorWithAlphaComponent:0.55]; glow.shadowBlurRadius = 26; glow.shadowOffset = NSZeroSize;
        [NSGraphicsContext saveGraphicsState]; [glow set]; [NSColor.blackColor setFill]; NSRectFill(r); [NSGraphicsContext restoreGraphicsState];
    }
    [NSColor.blackColor setFill]; NSRectFill(r);
    NSImage *shot = cd[@"image"];
    if (shot.size.width > 16) draw_cover(shot, r, sel ? 1 : hot ? 0.85 : ready ? 0.6 : 0.3, 0.78, 0.5, 0.35);   /* the place, above the HUD */
    NSGradient *foot = [[NSGradient alloc] initWithColorsAndLocations:[NSColor colorWithWhite:0 alpha:0], 0.0, [NSColor colorWithWhite:0 alpha:0.3], 0.42, ink(0.94), 1.0, nil];
    [foot drawInRect:r angle:90];
    if (!sel) { [ink(!ready ? 0.5 : hot ? 0.16 : 0.32) setFill]; fill_over(r); }
    NSColor *tc = sel || hot ? NSColor.whiteColor : [text_c() colorWithAlphaComponent:ready ? 0.82 : 0.5];
    draw_text(ready ? @"READY TO PLAY" : @"NOT INSTALLED", heading(11), sel || hot ? accent() : dim(), NSMakeRect(r.origin.x + 20, NSMaxY(r) - 92, 360, 16), NSTextAlignmentLeft, sh, 3.5);
    draw_text(cd[@"name"], heavy(25), tc, NSMakeRect(r.origin.x + 18, NSMaxY(r) - 74, r.size.width - 36, 36), NSTextAlignmentLeft, sh, 4);
    draw_text(ready ? cd[@"line"] : @"Install it from its disc to play it here", body(13, NO), sel || hot ? text_c() : dim(), NSMakeRect(r.origin.x + 20, NSMaxY(r) - 32, r.size.width - 40, 20), NSTextAlignmentLeft, sh, 0.2);
    [(sel ? accent() : hot ? [accent() colorWithAlphaComponent:0.7] : [accent_dim() colorWithAlphaComponent:ready ? 0.7 : 0.4]) setStroke];
    NSBezierPath *b = [NSBezierPath bezierPathWithRect:NSInsetRect(r, 0.5, 0.5)]; b.lineWidth = sel ? 1.5 : 1; [b stroke];
    if (sel) {
        brackets(NSInsetRect(r, -6, -6), foc ? 22 : 16, foc ? 3 : 2.5, accent());
        NSRect badge = NSMakeRect(NSMaxX(r) - 104, r.origin.y + 14, 90, 22);   /* SELECTED */
        [accent() setFill]; NSRectFill(badge);
        draw_text(@"SELECTED", heading(10.5), ink(1), NSMakeRect(badge.origin.x, badge.origin.y + 4, badge.size.width, 16), NSTextAlignmentCenter, nil, 2.5);
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
    NSString *val = t.summary ? t.summary() : c[@"label"]; CGFloat pt = 15;      /* made to fit a narrow tile */
    while (pt > 12 && [val sizeWithAttributes:@{NSFontAttributeName: body(pt, YES)}].width > r.size.width - 34) pt -= 0.5;
    draw_text(val, body(pt, YES), vc, NSMakeRect(r.origin.x + 17, r.origin.y + 34 + (15 - pt) / 2, r.size.width - 34, 24), NSTextAlignmentCenter, sh, 0.2);
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
    if (pn.linkTitle) {                                                  /* ADVANCED > · < GRAPHICS */
        NSRect lr = self.linkRect; BOOL lit = self.hover == HIT_PLINK || self.rowFocus == -1;
        [ink(lit ? 0.95 : 0.8) setFill]; fill_over(lr);
        [(lit ? accent() : accent_dim()) setStroke]; NSBezierPath *lb = [NSBezierPath bezierPathWithRect:NSInsetRect(lr, 0.5, 0.5)]; lb.lineWidth = 1; [lb stroke];
        if (self.rowFocus == -1) brackets(NSInsetRect(lr, -4, -4), 8, 2, accent());
        /* the word and a chevron drawn beside it (a font's ‹ › can be clipped) */
        NSDictionary *at = @{NSFontAttributeName: heading(12), NSKernAttributeName: @3};
        CGFloat tw = [pn.linkTitle sizeWithAttributes:at].width, gap = 10, cw = 5, x0 = NSMidX(lr) - (tw + gap + cw) / 2;
        CGFloat tx = pn.linkLeft ? x0 + cw + gap : x0, cx = pn.linkLeft ? x0 : x0 + tw + gap, cy = NSMidY(lr);
        draw_text(pn.linkTitle, heading(12), lit ? NSColor.whiteColor : text_c(), NSMakeRect(tx, lr.origin.y + 6, tw + 4, 18), NSTextAlignmentLeft, nil, 3);
        NSBezierPath *ch = [NSBezierPath bezierPath]; ch.lineWidth = 2; ch.lineCapStyle = NSLineCapStyleRound; ch.lineJoinStyle = NSLineJoinStyleRound;
        if (pn.linkLeft) { [ch moveToPoint:NSMakePoint(cx + cw, cy - 5)]; [ch lineToPoint:NSMakePoint(cx, cy)]; [ch lineToPoint:NSMakePoint(cx + cw, cy + 5)]; }
        else { [ch moveToPoint:NSMakePoint(cx, cy - 5)]; [ch lineToPoint:NSMakePoint(cx + cw, cy)]; [ch lineToPoint:NSMakePoint(cx, cy + 5)]; }
        [(lit ? NSColor.whiteColor : accent()) setStroke]; [ch stroke];
    }
    [[accent_dim() colorWithAlphaComponent:0.6] setFill]; fill_over(NSMakeRect(p.origin.x + 30, p.origin.y + 60, p.size.width - 60, 1));
    for (NSInteger k = 0; k < (NSInteger)self.rows.count; k++) {
        TSRow *t = self.rows[k]; NSRect r = [self rowRect:k]; NSDictionary *c = t.choices[t.index]; BOOL cycles = [self rowCycles:k];
        BOOL hot = cycles && self.hover >= HIT_ROW + 10 * k && self.hover <= HIT_ROW + 10 * k + 2, foc = cycles && self.rowFocus == k;
        if (foc || hot) { [[accent() colorWithAlphaComponent:foc ? 0.12 : 0.07] setFill]; fill_over(NSInsetRect(r, -10, -2));
                          if (foc) { [accent() setFill]; NSRectFill(NSMakeRect(r.origin.x - 10, r.origin.y - 2, 3, r.size.height + 4)); } }
        draw_text(t.title.uppercaseString, heading(15), foc || hot ? accent() : cycles ? text_c() : dim(), NSMakeRect(r.origin.x + 6, r.origin.y + 8, 300, 24), NSTextAlignmentLeft, sh, 3);
        if (cycles && t.choices.count > 1) {                                  /* a row that runs something has no arrows */
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
    if (self.open >= 0 && self.hover == HIT_PLINK) return self.panels[self.open].linkLeft ? @"Back to Graphics Options" : @"The renderer, and what is seldom changed";
    if (self.open >= 0) return @"←/→ change  ·  ↑/↓ move  ·  Return or Esc goes back";
    NSInteger k = -1;
    if (self.hover >= HIT_TILE && self.hover < HIT_ROW) k = (self.hover - HIT_TILE) / 10; else if (self.hover == HIT_NONE && self.focus >= 0) k = self.focus;
    if (k >= 0 && k < (NSInteger)self.tiles.count) { TSRow *t = self.tiles[k]; return t.choices[t.index][@"note"]; }
    if (self.hover >= HIT_CARD && self.hover < HIT_TILE) {
        NSInteger i = self.hover - HIT_CARD;
        return [self cardReady:i] ? [NSString stringWithFormat:@"%@: click to choose it, double-click to play.", self.cards[i][@"title"]]
                                  : [NSString stringWithFormat:@"%@: not installed (%@)", self.cards[i][@"title"], self.cards[i][@"missing"]];
    }
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
    /* the logo, its own glow beneath it; the project's name under it as its subtitle */
    if (self.logo.size.width > 16) {
        NSRect lr = fit_rect(self.logo, NSMakeRect(230, 16, 500, 132));
        if (self.glow.size.width > 16) [self.glow drawInRect:NSInsetRect(lr, -2, -2) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:0.85 respectFlipped:YES hints:nil];
        NSShadow *halo = [NSShadow new]; halo.shadowColor = [accent() colorWithAlphaComponent:0.45]; halo.shadowOffset = NSZeroSize; halo.shadowBlurRadius = 24;
        [NSGraphicsContext saveGraphicsState]; [halo set];
        [self.logo drawInRect:lr fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
        [NSGraphicsContext restoreGraphicsState];
    } else {                                                            /* no logo art yet: the name in type, made to fit */
        NSString *name = self.titleText.uppercaseString; CGFloat pt = 60;
        while (pt > 24 && [name sizeWithAttributes:@{NSFontAttributeName: heavy(pt), NSKernAttributeName: @8}].width > W - 80) pt -= 2;
        draw_text(name, heavy(pt), text_c(), NSMakeRect(0, 62 + (60 - pt) * 0.6, W, 80), NSTextAlignmentCenter, sh, 8);
    }
    draw_text(@"TIMESLIP", heavy(22), text_c(), NSMakeRect(0, 150, W, 30), NSTextAlignmentCenter, sh, 14);
    draw_text(@"NATIVE FOR APPLE SILICON  ·  RECOMPILED FROM YOUR XBOX DISC", heading(11.5), accent(), NSMakeRect(0, 184, W, 18), NSTextAlignmentCenter, sh, 4);
    draw_text(@"CHOOSE YOUR GAME", heading(10.5), dim(), NSMakeRect(60, 226, 400, 16), NSTextAlignmentLeft, sh, 3.5);
    draw_text(self.place.uppercaseString, heading(10.5), dim(), NSMakeRect(W - 460, 226, 400, 16), NSTextAlignmentRight, sh, 3.5);
    for (NSInteger i = 0; i < (NSInteger)self.cards.count; i++) [self drawCard:i shadow:sh];
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
enum { UPD_NONE, UPD_CHECKING, UPD_CURRENT, UPD_AVAILABLE, UPD_NORELEASE, UPD_ERROR };
static NSString *short_commit(NSString *c) { return c.length > 7 ? [c substringToIndex:7] : (c ?: @""); }
/* The updater's answer about GitHub's newest release, as its one line (mac/update.sh --check <installed commit>):
 * "available <tag> <commit>", "current <tag> <commit>", "none" or "error <why>"; nil if it could not be run. */
static NSString *update_check(NSString *updater, NSString *built)
{
    NSTask *t = [NSTask new]; t.executableURL = [NSURL fileURLWithPath:@"/bin/bash"]; t.arguments = @[updater, @"--check", built ?: @""];
    NSPipe *p = [NSPipe pipe]; t.standardOutput = p; t.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![t launchAndReturnError:nil]) return nil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 40 * NSEC_PER_SEC), dispatch_get_global_queue(0, 0), ^{ if (t.running) [t terminate]; });
    NSData *d = [p.fileHandleForReading readDataToEndOfFile]; [t waitUntilExit];
    NSString *out = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return t.terminationStatus == 0 && out.length ? [out componentsSeparatedByString:@"\n"].lastObject : nil;
}
static NSArray<NSDictionary *> *update_choice(int state, NSString *built, NSString *tag, NSString *why)
{
    NSString *label = @"Unavailable", *note = @"This copy wasn't installed from the repository (mac/install.sh)"; BOOL lit = NO;
    switch (state) {
    case UPD_CHECKING: label = @"Checking…"; note = @"Asking GitHub for the newest release"; break;
    case UPD_CURRENT: label = @"Up to Date"; note = built.length ? [NSString stringWithFormat:@"%@ (%@) · click to check again", tag, short_commit(built)]
                                                                  : [NSString stringWithFormat:@"%@ · click to check again", tag]; break;
    case UPD_AVAILABLE: label = @"Update Ready"; lit = YES; note = built.length ? [NSString stringWithFormat:@"%@ is out: click to install it (you have %@)", tag, short_commit(built)]
                                                                               : [NSString stringWithFormat:@"%@ is out: click to install it", tag]; break;
    case UPD_NORELEASE: label = @"No Release Yet"; note = @"Nothing has been released on GitHub yet · click to check again"; break;
    case UPD_ERROR: label = @"Can’t Check"; note = why.length ? [NSString stringWithFormat:@"%@ · click to retry", why] : @"GitHub unreachable: click to retry"; break;
    }
    return @[@{@"value": @"", @"label": label, @"note": note, @"accent": @(lit)}];
}
/* What the launcher shows for one of the update's lines: its "== " phases (mac/update.sh), as they are. */
static NSString *update_phase(NSString *line)
{
    return [line hasPrefix:@"== "] ? [line substringFromIndex:3] : nil;
}
@interface TSBlockTarget : NSObject
@property (copy) void (^fire)(void);
- (void)clicked:(id)b;
@end
@implementation TSBlockTarget
- (void)clicked:(id)b { (void)b; if (self.fire) self.fire(); }
@end
static BOOL update_run(NSWindow *parent, NSString *updater, NSString *logPath)   /* modal progress; YES when rebuilt */
{
    NSPanel *pn = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 520, 170) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    pn.title = @"Updating";
    NSTextField *title = [NSTextField labelWithString:@"Updating to the newest release"]; title.font = [NSFont boldSystemFontOfSize:14]; title.frame = NSMakeRect(20, 128, 480, 22);
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
                NSString *ph = update_phase(line); if (ph) on_main(^{ status.stringValue = ph; });
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
/* This Mac on its network: the first IPv4 address of an interface that is up, not loopback (en0 first). */
static NSString *lan_address(void)
{
    struct ifaddrs *list = NULL, *i; NSString *best = nil;
    if (getifaddrs(&list) != 0) return @"Not on a network";
    for (i = list; i; i = i->ifa_next) {
        if (!i->ifa_addr || i->ifa_addr->sa_family != AF_INET || !(i->ifa_flags & IFF_UP) || (i->ifa_flags & IFF_LOOPBACK)) continue;
        char buf[INET_ADDRSTRLEN]; inet_ntop(AF_INET, &((struct sockaddr_in *)i->ifa_addr)->sin_addr, buf, sizeof buf);
        if (!best || !strcmp(i->ifa_name, "en0")) best = @(buf);
        if (!strcmp(i->ifa_name, "en0")) break;
    }
    freeifaddrs(list);
    return best ?: @"Not on a network";
}
static TSRow *info(NSString *title, NSString *(^value)(void), NSString *note)
{
    TSRow *r = [TSRow new]; r.title = title; r.choices = @[@{@"value": @"", @"label": @"", @"note": note ?: @""}]; r.summary = value; return r;
}

/* The title's settings file, titles/<ID>.conf, which the game reads at start and its in-game menu writes: the
 * launcher's graphics and mouse rows are read from it and written back to it (README: "Running a build of your
 * own"), so a change made in either place is the one the other shows. Lines the launcher does not set (comments, the
 * picture, a title's own keys) are kept as they are. */
static NSMutableDictionary<NSString *, NSString *> *conf_read(NSString *path)
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSRange eq = [line rangeOfString:@"="];
        if (!line.length || [line hasPrefix:@"#"] || [line hasPrefix:@";"] || eq.location == NSNotFound) continue;
        NSString *k = [[line substringToIndex:eq.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *v = [[line substringFromIndex:eq.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (k.length) d[k.lowercaseString] = v;
    }
    return d;
}
static BOOL conf_write(NSString *path, NSDictionary<NSString *, NSString *> *vals)
{
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSMutableArray<NSString *> *lines = [[text componentsSeparatedByString:@"\n"] mutableCopy];
    if (lines.count && !lines.lastObject.length) [lines removeLastObject];
    NSMutableSet *done = [NSMutableSet set];
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = [lines[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSRange eq = [line rangeOfString:@"="];
        if (!line.length || [line hasPrefix:@"#"] || [line hasPrefix:@";"] || eq.location == NSNotFound) continue;
        NSString *k = [[line substringToIndex:eq.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].lowercaseString;
        if (!vals[k]) continue;
        lines[i] = [NSString stringWithFormat:@"%@ = %@", k, vals[k]]; [done addObject:k];
    }
    if (!text.length) [lines addObject:@"# Settings for this title: the launcher's and the in-game menu's (Esc). Delete the file for the defaults."];
    for (NSString *k in [vals.allKeys sortedArrayUsingSelector:@selector(compare:)])
        if (![done containsObject:k]) [lines addObject:[NSString stringWithFormat:@"%@ = %@", k, vals[k]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    return [[[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
static BOOL off_word(NSString *v)
{
    NSString *l = v.lowercaseString;
    return [l isEqual:@"0"] || [l isEqual:@"off"] || [l isEqual:@"no"] || [l isEqual:@"false"];
}

/* One game of the collection: where it is, what it remembers, and its own settings rows. TimeSplitters 2 and Future
 * Perfect each keep the data folder (~/Games/<…>Native: the disc's files in game/, the launcher's art in art/) and the
 * settings domain they had as two apps, so nothing is lost by the move to one. */
@interface TSGame : NSObject
@property NSString *key, *name, *cardName, *line, *place, *exe, *titleID, *dataPath, *confPath, *peerAddr, *missing;
@property NSUserDefaults *defaults;
@property BOOL ready;
@property NSImage *backdrop, *logo, *glow, *card;
@property NSArray<TSRow *> *tiles; @property NSArray<TSPanel *> *panels;
@property TSRow *display, *resolution, *widescreen, *filtering, *framerate, *soften, *interp, *fps, *renderer,
                *scheme, *mouse, *crosshair, *link, *router, *saves;
@end
@implementation TSGame
- (BOOL)kbm { return [self.scheme.value isEqual:@"1"]; }
@end

/* A row whose values are the settings file's own words: what the file says, else what this game's launcher
 * remembered before it used the file (`legacy`), else `dflt`. A value the file has that the row does not list (a
 * frame cap typed by hand, say) is added, so opening the launcher never changes it. */
static TSRow *conf_row(NSString *title, NSArray<NSDictionary *> *choices, NSString *have, NSString *legacy, NSString *dflt)
{
    NSString *v = have ?: legacy ?: dflt;
    if (index_of(choices, v, -1) < 0) choices = [choices arrayByAddingObject:@{@"value": v, @"label": v, @"note": @"As the settings file has it"}];
    return row(title, choices, v, index_of(choices, dflt, 0));
}

@interface Launcher : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window; @property (strong) TSLaunchView *view;
@property (strong) NSArray<TSGame *> *games; @property NSInteger current;
@property NSString *lastPickPath;                   /* <user dir>/launcher_game.txt: the game last picked, "ts2" or "fp" (the PC's launcher keeps it there too) */
@property (strong) TSRow *updates;
@end

@implementation Launcher
- (TSGame *)game { return self.games[self.current]; }
/* The settings domain a game's launcher used as its own app; a test (TS2_LAUNCHER_PREFS=<prefix>) gets its own. */
static NSUserDefaults *domain(NSString *bundleID)
{
    const char *test = getenv("TS2_LAUNCHER_PREFS");
    if (test && *test) return [[NSUserDefaults alloc] initWithSuiteName:[NSString stringWithFormat:@"%s.%@", test, bundleID]];
    if ([bundleID isEqual:NSBundle.mainBundle.bundleIdentifier]) return NSUserDefaults.standardUserDefaults;
    return [[NSUserDefaults alloc] initWithSuiteName:bundleID];
}
- (TSGame *)gameWithKey:(NSString *)key name:(NSString *)name card:(NSString *)card line:(NSString *)line place:(NSString *)place
                    exe:(NSString *)exe titleID:(NSString *)tid bundleID:(NSString *)bid data:(NSString *)defData
{
    NSDictionary *plist = NSBundle.mainBundle.infoDictionary;
    TSGame *g = [TSGame new]; g.key = key; g.name = name; g.cardName = card; g.line = line; g.place = place; g.exe = exe; g.titleID = tid;
    /* the data folder: install.sh's (Timeslip<KEY>Data; TS2DataPath in a one-game app), or a test's
     * (TS2_DATA_PATH_<KEY>, or TS2_DATA_PATH for the app's own game) */
    NSString *pkey = [NSString stringWithFormat:@"Timeslip%@Data", key.uppercaseString];
    NSString *data = plist[pkey];
    BOOL ownGame = [plist[@"TS2Exe"] ?: @"timeslip" isEqual:exe];
    if (!data && ownGame) data = plist[@"TS2DataPath"];
    const char *env = getenv([NSString stringWithFormat:@"TS2_DATA_PATH_%@", key.uppercaseString].UTF8String);
    if (env && *env) data = @(env);
    else if (ownGame && getenv("TS2_DATA_PATH")) data = @(getenv("TS2_DATA_PATH"));
    g.dataPath = [(data ?: defData) stringByExpandingTildeInPath];
    /* its settings file: the game's own (~/Library/Application Support/xboxrecomp/titles/<ID>.conf); a test's
     * folder of them (TS2_CONF_DIR), or the one RECOMP_DISPLAY_CONFIG names */
    NSString *file = [NSString stringWithFormat:@"%@.conf", tid.uppercaseString];
    if (getenv("TS2_CONF_DIR")) g.confPath = [@(getenv("TS2_CONF_DIR")) stringByAppendingPathComponent:file];
    else if (getenv("RECOMP_DISPLAY_CONFIG") && *getenv("RECOMP_DISPLAY_CONFIG")) g.confPath = @(getenv("RECOMP_DISPLAY_CONFIG"));
    else g.confPath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/xboxrecomp/titles"] stringByAppendingPathComponent:file];
    g.defaults = domain(bid);
    [g.defaults registerDefaults:@{@"fullscreen": @NO, @"scale": @2, @"widescreen": @YES, @"aniso": @8, @"cap": @"adaptive", @"interp": @0,
                                   @"soften": @"sharp", @"fps": @NO, @"scheme": @"kbm", @"mouse": @80, @"crosshair": @YES, @"link": @"off",
                                   @"peer": @"", @"upnp": @NO}];
    NSString *macos = NSBundle.mainBundle.executablePath.stringByDeletingLastPathComponent;
    BOOL haveExe = [[NSFileManager defaultManager] isExecutableFileAtPath:[macos stringByAppendingPathComponent:exe]];
    BOOL haveDisc = [[NSFileManager defaultManager] fileExistsAtPath:[g.dataPath stringByAppendingPathComponent:@"game/default.xbe"]];
    g.ready = haveExe && haveDisc;
    g.missing = !haveExe ? @"this app was built without it (mac/install.sh)"
                         : [NSString stringWithFormat:@"no disc files in %@", [[g.dataPath stringByAppendingPathComponent:@"game"] stringByAbbreviatingWithTildeInPath]];
    NSArray *artDirs = @[[g.dataPath stringByAppendingPathComponent:@"art"],
                         [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:[@"art_" stringByAppendingString:key]] ?: @"",
                         ownGame ? [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"art"] ?: @"" : @""];
    g.backdrop = image_at(artDirs, @"backdrop.jpg"); g.logo = image_at(artDirs, @"logo.png"); g.glow = image_at(artDirs, @"glow.png");
    g.card = image_at(artDirs, @"card_vulkan.jpg") ?: image_at(artDirs, @"card_metal.jpg") ?: g.backdrop;
    [self buildRows:g];
    return g;
}
- (void)buildRows:(TSGame *)g
{
    NSUserDefaults *d = g.defaults; NSDictionary<NSString *, NSString *> *c = conf_read(g.confPath);
    NSString *(^b)(NSString *) = ^NSString *(NSString *k) { return c[k] ? (off_word(c[k]) ? @"0" : @"1") : nil; };   /* a yes/no line */
    NSString *(^old)(NSString *) = ^NSString *(NSString *k) { return [d objectForKey:k] ? [NSString stringWithFormat:@"%@", [d objectForKey:k]] : nil; };
    NSString *(^oldb)(NSString *) = ^NSString *(NSString *k) { return [d objectForKey:k] ? ([d boolForKey:k] ? @"1" : @"0") : nil; };

    /* Graphics Options */
    g.display = conf_row(@"Display", @[@{@"value": @"0", @"label": @"Window", @"note": @"A window on the desktop; Alt-Return switches in the game"},
                                       @{@"value": @"1", @"label": @"Full Screen", @"note": @"The whole display, Dock and menu bar out of the way"}], b(@"fullscreen"), oldb(@"fullscreen"), @"0");
    NSMutableArray *res = [NSMutableArray array];
    for (int s = 1; s <= 4; s++)
        [res addObject:@{@"value": [NSString stringWithFormat:@"%d", s], @"label": [NSString stringWithFormat:@"%dx  ·  %d × %d", s, 640 * s, 480 * s], @"short": [NSString stringWithFormat:@"%dx", s],
                         @"note": s == 1 ? @"The console's own 640 × 480: softest, lightest on the GPU" : s == 2 ? @"Sharp on a Retina display at little cost (recommended)"
                                : s == 3 ? @"Sharper still; for a larger window or full screen" : @"Supersampled: the cleanest edges, the most GPU work"}];
    g.resolution = conf_row(@"Resolution", res, c[@"resolution_scale"], old(@"scale"), @"2");
    g.widescreen = conf_row(@"Widescreen", @[@{@"value": @"1", @"label": @"16:9", @"note": @"A wider camera, not a stretched one; menus and HUD laid out for it"},
                                             @{@"value": @"0", @"label": @"4:3", @"note": @"The picture as the console drew it"}], b(@"widescreen"), oldb(@"widescreen"), @"1");
    g.filtering = conf_row(@"Texture Filtering", @[@{@"value": @"1", @"label": @"Console", @"short": @"Console Filtering", @"note": @"The game's own filtering"},
                                                   @{@"value": @"4", @"label": @"4x Anisotropic", @"short": @"4x AF", @"note": @"Floors and walls stay sharp at an angle"},
                                                   @{@"value": @"8", @"label": @"8x Anisotropic", @"short": @"8x AF", @"note": @"Floors and walls stay sharp at an angle"},
                                                   @{@"value": @"16", @"label": @"16x Anisotropic", @"short": @"16x AF", @"note": @"The sharpest; costs a little GPU time"}],
                           c[@"anisotropy"], old(@"aniso"), @"8");
    g.soften = conf_row(@"Post-processing", @[@{@"value": @"sharp", @"label": @"Sharp", @"note": @"The game's soften pass, one screen pixel wide at any resolution"},
                                              @{@"value": @"console", @"label": @"As the console", @"note": @"The soften pass a console pixel wide: softer, as the game looked on a TV"},
                                              @{@"value": @"off", @"label": @"Off", @"note": @"No soften pass: the crispest picture"}], c[@"post_soften"], old(@"soften"), @"sharp");
    g.framerate = conf_row(@"Frame Rate", @[@{@"value": @"adaptive", @"label": @"Adaptive", @"note": @"60 where the game ran at 60, paced the way the console paced it"},
                                            @{@"value": @"60", @"label": @"60 fps", @"note": @"Every frame at 60"},
                                            @{@"value": @"30", @"label": @"30 fps", @"note": @"Half the work: steadier on a busy or older Mac"}], c[@"frame_cap"], old(@"cap"), @"adaptive");
    NSString *oldInterp = old(@"interp"); if ([oldInterp isEqual:@"0"]) oldInterp = @"1";      /* the launcher's 0 was the file's 1: off */
    g.interp = conf_row(@"Frame Interpolation", @[@{@"value": @"1", @"label": @"Off", @"note": @"Each frame the game draws, shown once"},
                                                  @{@"value": @"2", @"label": @"2x", @"note": @"Twice the frames on screen while the game runs at 60: for 120 Hz displays"},
                                                  @{@"value": @"3", @"label": @"3x", @"note": @"Three frames for each the game draws"},
                                                  @{@"value": @"4", @"label": @"4x", @"note": @"Four frames for each the game draws"}], c[@"frame_interp"], oldInterp, @"1");
    g.fps = conf_row(@"FPS Counter", @[@{@"value": @"0", @"label": @"Off", @"note": @"F9 shows it in the game"},
                                       @{@"value": @"1", @"label": @"On", @"note": @"The frame rate in the corner; F9 hides it"}], b(@"fps_overlay"), oldb(@"fps"), @"0");
    TSPanel *gp = [TSPanel new]; gp.title = @"GRAPHICS OPTIONS";
    gp.rows = @[g.display, g.resolution, g.widescreen, g.filtering, g.soften, g.framerate, g.interp, g.fps];
    gp.linkTitle = @"ADVANCED"; gp.linkPanel = 3;
    /* Advanced: the renderer. Metal is the Mac's; Vulkan through MoltenVK is kept here for a Mac Metal does not suit.
     * `moltenvk`, not `vulkan`: an old file's `vulkan` stays Metal (recompose's rhi.c). */
    NSString *rv = c[@"renderer"] && [c[@"renderer"].lowercaseString isEqual:@"moltenvk"] ? @"moltenvk" : (c[@"renderer"] ? @"metal" : nil);
    g.renderer = conf_row(@"Renderer", @[@{@"value": @"metal", @"label": @"Metal (default)", @"short": @"Metal", @"note": @"Apple's own graphics API, drawn by the port's own renderer: nothing in between"},
                                         @{@"value": @"moltenvk", @"label": @"Vulkan (MoltenVK)", @"short": @"MoltenVK", @"note": @"The Vulkan renderer through MoltenVK; Metal again if it cannot start"}],
                          rv, nil, @"metal");
    TSPanel *ap = [TSPanel new]; ap.title = @"ADVANCED OPTIONS"; ap.rows = @[g.renderer];
    ap.linkTitle = @"GRAPHICS"; ap.linkPanel = 0; ap.linkLeft = YES;
    ap.footnote = @"The renderer changes from the next start. The in-game menu (Esc) has it too, under Display › Advanced.";

    /* Controls */
    /* Keyboard & Mouse is mouse look (`mouse_look`, the game's default): the mouse turns the view. The keys are the
     * game's own either way (its title_defaults.c, or a bindings file, titles/<ID>.input.json), and a controller
     * works beside them. */
    NSString *oldScheme = [d objectForKey:@"scheme"] ? ([[d stringForKey:@"scheme"] isEqual:@"pad"] ? @"0" : @"1") : nil;
    g.scheme = conf_row(@"Scheme", @[@{@"value": @"1", @"label": @"Keyboard & Mouse", @"note": @"The mouse turns the view; the keys below, and a controller still works beside them"},
                                     @{@"value": @"0", @"label": @"Controller", @"note": @"The right stick turns the view; the mouse is left to the menus"}], b(@"mouse_look"), oldScheme, @"1");
    NSMutableArray *ms = [NSMutableArray array];
    for (NSString *m in @[@"40", @"60", @"80", @"100"]) [ms addObject:@{@"value": m, @"label": [m isEqual:@"80"] ? @"80 (default)" : m, @"note": @"How far the view turns for the mouse's travel"}];
    g.mouse = conf_row(@"Mouse Speed", ms, c[@"mouse_sensitivity"], old(@"mouse"), @"80");
    g.crosshair = conf_row(@"Crosshair", @[@{@"value": @"1", @"label": @"Always", @"note": @"With the mouse, the aiming crosshair stays in the middle of the screen"},
                                           @{@"value": @"0", @"label": @"While Aiming", @"note": @"Only while aiming, as the game drew it; online, both players need the same"}],
                           b(@"crosshair"), oldb(@"crosshair"), @"1");
    __weak TSGame *wg = g;
    /* the game's own keys (its title_defaults.c), as the PC's launcher shows them */
    BOOL fp = [g.key isEqual:@"fp"];
    TSRow *move = info(@"Move · Look", ^{ return wg.kbm ? (fp ? @"W A S D  ·  Mouse or I J K L" : @"W A S D  ·  Mouse") : @"Left Stick  ·  Right Stick"; }, nil);
    TSRow *fire = info(@"Fire · Secondary", ^{ return wg.kbm ? (fp ? @"Left Click or H  ·  G" : @"Left Click  ·  G or Middle Click") : @"Right Trigger  ·  Left Trigger"; }, nil);
    TSRow *abxy = info(fp ? @"A · B · X · Y" : @"A · B · Y", ^{ return wg.kbm ? (fp ? @"F, E, Space  ·  V, Backspace  ·  R  ·  Y" : @"F, E, Space  ·  Backspace  ·  R")
                                                                    : @"The pad's own"; }, nil);
    TSRow *wb = info(fp ? @"White · Black · Sticks" : @"Stick Clicks", ^{ return wg.kbm ? (fp ? @"T  ·  B  ·  Right Click, Shift / C, Ctrl" : @"Right Click  ·  C or Ctrl")
                                                                            : fp ? @"Shoulders  ·  Stick Clicks" : @"Stick Clicks"; }, nil);
    TSRow *menus = info(@"Start · Back · Menus", ^{ return wg.kbm ? (fp ? @"Return or P  ·  Tab  ·  Arrows" : @"Return or Tab  ·  Backspace  ·  Arrows")
                                                                  : @"Start  ·  Back  ·  D-Pad"; }, nil);
    TSPanel *cp = [TSPanel new]; cp.title = @"CONTROLS"; cp.rows = @[g.scheme, g.mouse, g.crosshair, move, fire, abxy, wb, menus];
    cp.footnote = @"In the game: 1-9 weapons · the wheel swaps or zooms · Esc the PC menu · F9 frame rate · F11 screenshot · Alt-Return full screen";
    /* Play Together: System Link (the game's own LAN play, over the network or the internet) and online co-op (each
     * machine runs the whole game and sends only its controller). Chosen for each start, so given to the game as
     * RECOMP_SYSLINK / RECOMP_SYSLINK_HOST / RECOMP_SYSLINK_UPNP and RECOMP_LOCKSTEP_NET / RECOMP_LOCKSTEP_PEER. */
    g.link = row(@"Mode", @[@{@"value": @"off", @"label": @"Off", @"note": @"Play on this Mac alone"},
                            @{@"value": @"host", @"label": @"System Link: Host", @"short": @"Link Host", @"note": @"Others join this Mac's System Link game (UDP 27610)"},
                            @{@"value": @"join", @"label": @"System Link: Join", @"short": @"Link Join", @"note": @"Join the System Link game at the host's address below"},
                            @{@"value": @"coop-host", @"label": @"Co-op: Host", @"short": @"Co-op Host", @"note": @"Story co-op online: this Mac plays controller 1, the other machine joins (UDP 27620)"},
                            @{@"value": @"coop-join", @"label": @"Co-op: Join", @"short": @"Co-op Join", @"note": @"Story co-op online: join the host below as controller 2"}],
                 [d stringForKey:@"link"], 0);
    g.peerAddr = [d stringForKey:@"peer"] ?: @"";
    __weak Launcher *wl = self;
    TSRow *peer = [TSRow new]; peer.title = @"Host's Address";
    peer.choices = @[@{@"value": @"", @"label": @"", @"note": @"When joining: the hosting machine's address, with :port if not the usual one"}];
    peer.summary = ^NSString * { return wg.peerAddr.length ? wg.peerAddr : @"Click to Type It"; };
    peer.activate = ^{ [wl askPeer]; };
    g.router = row(@"Router", @[@{@"value": @NO, @"label": @"Leave It", @"note": @"Hosting on your own network: nothing to open"},
                                @{@"value": @YES, @"label": @"Open the Port (UPnP)", @"short": @"UPnP", @"note": @"Hosting for friends on the internet: the router is asked to forward the port"}],
                   @([d boolForKey:@"upnp"]), 0);
    TSRow *me = info(@"This Mac", ^{ return lan_address(); }, @"When hosting, the other player joins this address");
    TSPanel *np = [TSPanel new]; np.title = @"PLAY TOGETHER"; np.rows = @[g.link, peer, g.router, me];
    np.footnote = @"Both machines need this same version. The first time you host, macOS asks to allow incoming connections.";
    g.panels = @[gp, cp, np, ap];

    TSRow *gfx = [TSRow new]; gfx.title = @"Graphics Options"; gfx.wide = YES;
    gfx.choices = @[@{@"value": @"", @"label": @"", @"note": @"Display, resolution, widescreen, filtering, post-processing, frame rate, interpolation; the renderer under Advanced"}];
    gfx.summary = ^NSString * {
        NSMutableArray *a = [NSMutableArray array];
        for (TSRow *t in @[wg.display, wg.resolution, wg.widescreen, wg.filtering]) [a addObject:t.choices[t.index][@"short"] ?: t.choices[t.index][@"label"]];
        return [a componentsJoinedByString:@"  ·  "];
    };
    gfx.activate = ^{ [wl.view openPanel:0]; };
    TSRow *controls = [TSRow new]; controls.title = @"Controls";
    controls.choices = @[@{@"value": @"", @"label": @"", @"note": @"Keyboard & Mouse or a controller, and which key does what"}];
    controls.summary = ^NSString * { return wg.kbm ? @"Keys & Mouse" : @"Controller"; };
    controls.activate = ^{ [wl.view openPanel:1]; };
    TSRow *net = [TSRow new]; net.title = @"Play Together";
    net.choices = @[@{@"value": @"", @"label": @"", @"note": @"System Link and online co-op with another Mac or PC"}];
    net.summary = ^NSString * { NSDictionary *ch = wg.link.choices[wg.link.index]; return ch[@"short"] ?: ch[@"label"]; };
    net.activate = ^{ [wl.view openPanel:2]; };
    /* the game's own save folder: UDATA/<its title id> */
    NSString *saves = [g.dataPath stringByAppendingPathComponent:[@"game/UDATA" stringByAppendingPathComponent:g.titleID.lowercaseString]];
    g.saves = [TSRow new]; g.saves.title = @"Saves";
    g.saves.choices = @[@{@"value": @"", @"label": @"Open", @"note": [@"Your profiles and story progress: " stringByAppendingString:[saves stringByAbbreviatingWithTildeInPath]]}];
    g.saves.activate = ^{ [[NSFileManager defaultManager] createDirectoryAtPath:saves withIntermediateDirectories:YES attributes:nil error:nil];
                          [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:saves isDirectory:YES]]; };
    g.tiles = @[gfx, controls, net, g.saves];
}
- (void)showGame:(NSInteger)i
{
    self.current = i; TSGame *g = self.game; TSLaunchView *v = self.view;
    v.card = i; v.backdrop = g.backdrop; v.logo = g.logo; v.glow = g.glow; v.titleText = g.name; v.place = g.place;
    v.tiles = [g.tiles arrayByAddingObject:self.updates]; v.panels = g.panels;
    v.needsDisplay = YES;
}
- (void)applicationDidFinishLaunching:(NSNotification *)n
{
    NSString *userDir = getenv("TS2_CONF_DIR") ? @(getenv("TS2_CONF_DIR")).stringByDeletingLastPathComponent   /* a test's: beside its titles/ */
                                               : [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/xboxrecomp"];
    self.lastPickPath = [userDir stringByAppendingPathComponent:@"launcher_game.txt"];
    self.games = @[
        [self gameWithKey:@"ts2" name:@"TimeSplitters 2" card:@"TIMESPLITTERS 2" line:@"Story · Arcade · Challenge · online co-op"
                    place:@"1990 · Siberia · Oblask Dam" exe:@"timeslip" titleID:@"4553000A" bundleID:@"io.github.joshspeakman.timesplitters2"
                     data:@"~/Games/TimeSplitters2Native"],
        [self gameWithKey:@"fp" name:@"TimeSplitters Future Perfect" card:@"FUTURE PERFECT" line:@"Story · Arcade · Challenge · MapMaker · online co-op"
                    place:@"2401 · Time to Split" exe:@"timeslip_fp" titleID:@"45410066" bundleID:@"io.github.joshspeakman.timesplitters-fp"
                     data:@"~/Games/TimeSplittersFPNative"]];

    TSLaunchView *v = [[TSLaunchView alloc] initWithFrame:NSMakeRect(0, 0, W, H)]; self.view = v;
    v.hover = v.pressed = HIT_NONE; v.focus = -1; v.open = -1;
    NSMutableArray *cards = [NSMutableArray array];
    for (TSGame *g in self.games)
        [cards addObject:@{@"name": g.cardName, @"title": g.name, @"line": g.line, @"image": g.card ?: [NSImage new], @"ready": @(g.ready), @"missing": g.missing}];
    v.cards = cards;
    v.hint = @"←/→ game · ↑/↓ settings · Return plays · Esc quits";
    [self setupUpdates];
    /* the game picked last time, if it is still here; else the first that is (a one-game app: its own) */
    NSInteger pick = -1; NSString *last = getenv("TS2_LAUNCHER_GAME") ? @(getenv("TS2_LAUNCHER_GAME")) : [[NSString stringWithContentsOfFile:self.lastPickPath encoding:NSUTF8StringEncoding error:nil]
                                                                                       stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *own = NSBundle.mainBundle.infoDictionary[@"TS2Exe"];
    for (NSInteger i = 0; i < (NSInteger)self.games.count; i++) if ([self.games[i].key isEqual:last] && self.games[i].ready) pick = i;
    for (NSInteger i = 0; pick < 0 && i < (NSInteger)self.games.count; i++) if (own && [self.games[i].exe isEqual:own] && self.games[i].ready) pick = i;
    for (NSInteger i = 0; pick < 0 && i < (NSInteger)self.games.count; i++) if (self.games[i].ready) pick = i;
    [self showGame:MAX(pick, 0)];
    __weak Launcher *ws = self;
    v.onPlay = ^{ [ws play]; };
    v.onQuit = ^{ [NSApp terminate:nil]; };
    v.onChange = ^{ [ws save]; };
    v.onSelect = ^(NSInteger i) {
        [ws showGame:i];
        [[NSFileManager defaultManager] createDirectoryAtPath:ws.lastPickPath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [[ws.game.key stringByAppendingString:@"\n"] writeToFile:ws.lastPickPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    };

    const char *shot = getenv("TS2_LAUNCHER_SHOT");
    if (shot) {                                                          /* development: the window as an image */
        if (getenv("TS2_LAUNCHER_HOVER")) v.hover = atoi(getenv("TS2_LAUNCHER_HOVER"));
        if (getenv("TS2_LAUNCHER_PANEL")) [v openPanel:atoi(getenv("TS2_LAUNCHER_PANEL"))];
        if (getenv("TS2_LAUNCHER_ROWFOCUS")) v.rowFocus = atoi(getenv("TS2_LAUNCHER_ROWFOCUS"));
        NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds]; [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(shot) atomically:YES];
        exit(0);
    }
    if (getenv("TS2_LAUNCHER_PLAY")) { [self play]; return; }    /* development: Play at once, no window to take the focus */
    NSWindow *w = [[NSWindow alloc] initWithContentRect:v.frame styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskFullSizeContentView
                                                backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO; w.titlebarAppearsTransparent = YES; w.titleVisibility = NSWindowTitleHidden; w.movableByWindowBackground = YES;
    w.title = NSBundle.mainBundle.infoDictionary[@"CFBundleName"] ?: @"Timeslip"; w.backgroundColor = NSColor.blackColor; w.contentView = v;
    self.window = w; [w center]; [w makeKeyAndOrderFront:nil]; [w makeFirstResponder:v];
    [NSApp activateIgnoringOtherApps:YES];
}
- (void)setupUpdates
{
    NSDictionary *infoPlist = NSBundle.mainBundle.infoDictionary;
    NSString *updater = [NSBundle.mainBundle.executablePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"update"];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:updater]) updater = nil;
    NSString *built = infoPlist[@"TS2Built"] ?: @"";
    TSRow *u = [TSRow new]; u.title = @"Updates"; self.updates = u;
    __block int state = updater ? UPD_CHECKING : UPD_NONE; __block NSString *tag = nil;
    u.choices = update_choice(state, built, nil, nil);
    __weak TSRow *wu = u; __weak Launcher *ws = self;
    void (^check)(void) = ^{
        if (!updater) return;
        state = UPD_CHECKING; wu.choices = update_choice(state, built, nil, nil); ws.view.needsDisplay = YES;
        void (^done)(NSString *) = ^(NSString *line) {
            NSArray<NSString *> *w = [line componentsSeparatedByString:@" "]; NSString *why = nil;
            if (!line) state = UPD_ERROR;
            else if ([w[0] isEqual:@"none"]) state = UPD_NORELEASE;
            else if (w.count >= 3 && [w[0] isEqual:@"current"]) { state = UPD_CURRENT; tag = w[1]; }
            else if (w.count >= 3 && [w[0] isEqual:@"available"]) { state = UPD_AVAILABLE; tag = w[1]; }
            else { state = UPD_ERROR; if ([w[0] isEqual:@"error"] && line.length > 6) why = [line substringFromIndex:6]; }
            wu.choices = update_choice(state, built, tag, why); ws.view.needsDisplay = YES;
        };
        if (getenv("TS2_LAUNCHER_SHOT")) { done(update_check(updater, built)); return; }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ NSString *l = update_check(updater, built); on_main(^{ done(l); }); });
    };
    check();
    u.activate = ^{
        if (state == UPD_CHECKING || state == UPD_NONE) return;
        if (state != UPD_AVAILABLE) { check(); return; }
        NSAlert *a = [NSAlert new];
        a.messageText = [NSString stringWithFormat:@"Update to %@?", tag];
        a.informativeText = @"The release is downloaded from GitHub and the app is rebuilt from your own copy of the games, "
                             "which takes a few minutes. Your saves and settings are kept. The app restarts when it is done.";
        [a addButtonWithTitle:@"Update"]; [a addButtonWithTitle:@"Cancel"];
        if ([a runModal] != NSAlertFirstButtonReturn) return;
        if (update_run(ws.window, updater, [ws.game.dataPath stringByAppendingPathComponent:@"update.log"])) {
            NSTask *o = [NSTask new]; o.executableURL = [NSURL fileURLWithPath:@"/usr/bin/open"]; o.arguments = @[@"-n", NSBundle.mainBundle.bundlePath];
            [o launchAndReturnError:nil]; [o waitUntilExit];
            exit(0);
        }
        check();
    };
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)a { return YES; }
/* Graphics and mouse into the game's settings file; the rest (scheme, Play Together) into its settings domain. */
- (void)save
{
    TSGame *g = self.game; NSUserDefaults *d = g.defaults;
    conf_write(g.confPath, @{@"fullscreen": g.display.value, @"resolution_scale": g.resolution.value, @"widescreen": g.widescreen.value,
                             @"anisotropy": g.filtering.value, @"post_soften": g.soften.value, @"frame_cap": g.framerate.value,
                             @"frame_interp": g.interp.value, @"fps_overlay": g.fps.value, @"renderer": g.renderer.value,
                             @"mouse_look": g.scheme.value, @"mouse_sensitivity": g.mouse.value, @"crosshair": g.crosshair.value});
    [d removeObjectForKey:@"renderer"];                                 /* from when the Mac also had Vulkan */
    [d setObject:g.kbm ? @"kbm" : @"pad" forKey:@"scheme"];
    [d setObject:g.link.value forKey:@"link"];
    [d setObject:g.peerAddr ?: @"" forKey:@"peer"];
    [d setBool:[g.router.value boolValue] forKey:@"upnp"];
    [d synchronize];
}
- (void)askPeer
{
    TSGame *g = self.game;
    NSAlert *a = [NSAlert new]; a.messageText = @"The host's address";
    a.informativeText = @"The address of the machine that is hosting (its launcher shows it under This Mac), with :port if it is not the usual one.";
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)]; f.stringValue = g.peerAddr ?: @""; f.placeholderString = @"192.168.1.20";
    a.accessoryView = f; [a addButtonWithTitle:@"OK"]; [a addButtonWithTitle:@"Cancel"];
    [a.window setInitialFirstResponder:f];
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    g.peerAddr = [f.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self save]; self.view.needsDisplay = YES;
}
- (void)play
{
    TSGame *g = self.game;
    if (!g.ready) {
        NSAlert *a = [NSAlert new]; a.messageText = [NSString stringWithFormat:@"%@ is not installed", g.name];
        a.informativeText = [NSString stringWithFormat:@"Its %@.", g.missing]; [a runModal]; return;
    }
    [self save];
    NSString *mode = g.link.value;
    if (([mode isEqual:@"join"] || [mode isEqual:@"coop-join"]) && !g.peerAddr.length) {
        [self.view openPanel:2]; [self askPeer];
        if (!g.peerAddr.length) return;
    }
    NSString *game = [g.dataPath stringByAppendingPathComponent:@"game"];
    setenv("RECOMP_GAME_DIR", game.fileSystemRepresentation, 1);
    /* the graphics come from the settings file, as the launcher just wrote it; a test's folder of them is the game's too */
    if (getenv("TS2_CONF_DIR")) setenv("RECOMP_DISPLAY_CONFIG", g.confPath.fileSystemRepresentation, 1);
    /* Play Together: the launcher decides, so a setting left in the settings file does not */
    BOOL coop = [mode hasPrefix:@"coop-"], hosts = [mode hasSuffix:@"host"], joins = [mode hasSuffix:@"join"];
    setenv("RECOMP_SYSLINK", coop || [mode isEqual:@"off"] ? "off" : mode.UTF8String, 1);
    setenv("RECOMP_LOCKSTEP_NET", coop ? (hosts ? "host" : "join") : "off", 1);
    setenv("RECOMP_SYSLINK_UPNP", hosts && [g.router.value boolValue] ? "1" : "0", 1);
    unsetenv("RECOMP_SYSLINK_HOST"); unsetenv("RECOMP_LOCKSTEP_PEER");
    if (joins) setenv(coop ? "RECOMP_LOCKSTEP_PEER" : "RECOMP_SYSLINK_HOST", g.peerAddr.UTF8String, 1);
    [self.window orderOut:nil];
    NSString *exe = [NSBundle.mainBundle.executablePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:g.exe];
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
