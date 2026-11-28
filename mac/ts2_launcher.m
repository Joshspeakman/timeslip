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
 * Development: mac/README.md ("Development"): TS2_LAUNCHER_SHOT, _GAME, _FOCUS, _EXTRAS, _PANEL, _ROWFOCUS, _HOVER, _PLAY;
 * TS2_CONF_DIR, TS2_LAUNCHER_PREFS and TS2_DATA_PATH_<TS2|FP> keep a test off the player's own settings and games. */
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#include "net_upnp.h"                                      /* recompose src/net: the router's address, as the Windows launcher asks it */
#include <unistd.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/if.h>

static void on_main(dispatch_block_t b) { CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, b); CFRunLoopWakeUp(CFRunLoopGetMain()); }

// ---------------------------------------------------------------- settings
@interface TSRow : NSObject
@property NSString *title; @property NSArray<NSDictionary *> *choices; @property NSInteger index;
@property NSString *placeholder;                    /* a text row's dim words while it is empty ("type a code") */
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
/* The hero layout, as the Windows launcher's (recompose src/launcher/launcher_hero.inc, with this repository's
 * src/launcher_games.c): the game's key art across the whole window, slowly moving and handing over to the next, the
 * logo bottom-left sitting on a menu row across the bottom, the other game's logo above the row's right end, and the
 * settings in a column at the right. Window units are the Windows launcher's: 1280 by 720. */
enum { W = 1280, H = 720, ROW_X = 60, ROW_Y = H - 116, ROW_H = 50, ROW_GAP = 34, ROW_R = W - 64,
       PANEL_X = 610, PANEL_W = W - 64 - 610, ROWS_Y = 134, PITCH = 46,
       EX_COLS = 4, EX_TW = 268, EX_TH = 151, EX_GAP = 24, EX_X0 = 64, EX_Y0 = 200, EX_PITCH = EX_TH + 66, EX_ROWS = 2 };
enum { HIT_NONE = -1, HIT_QUIT = 101, HIT_BACK = 102, HIT_PLINK = 103, HIT_SWITCH = 104, HIT_OPEN = 105, HIT_FOLDER = 106, HIT_PRICES = 107, HIT_SHARE = 108, HIT_CMD = 800,
       HIT_ITEM = 200, HIT_ROW = 400, HIT_SECTION = 600, HIT_TILE = 700 };          /* HIT_ROW + 10*k + 0 left / 1 value / 2 right */
enum { IT_PLAY, IT_GRAPHICS, IT_CONTROLS, IT_ONLINE, IT_SAVES, IT_EXTRAS, IT_UPDATES, IT_QUIT };
#define HOLD 11.0                                         /* s a picture is up */
#define FADE 1.8                                          /* the hand-over to the next */
#define SWITCH 0.7                                        /* another game's: quicker, with a slide */
#define SLIDE 70.0                                        /* how far, in window units */
#define DOT @"  ·  "

static NSColor *rgb(uint32_t c, CGFloat a) { return [NSColor colorWithSRGBRed:((c >> 16) & 255) / 255.0 green:((c >> 8) & 255) / 255.0 blue:(c & 255) / 255.0 alpha:a]; }
static const uint32_t INK = 0x040812;
static uint32_t brighter(uint32_t c)              /* halfway to white: the focused row's edge, the captions */
{
    uint32_t r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
    r += (255 - r) / 2; g += (255 - g) / 2; b += (255 - b) / 2;
    return (r << 16) | (g << 8) | b;
}
static double ease(double t) { t = t < 0 ? 0 : t > 1 ? 1 : t; return t * t * (3 - 2 * t); }
static double now_s(void) { return CACurrentMediaTime(); }

/* The faces (the Windows launcher's display, heavy, condensed and body faces), in Avenir Next. */
enum { F_BODY, F_DISPLAY, F_HEAVY, F_COND, F_COND_BOLD };
static NSFont *face(int f, CGFloat pt)
{
    static NSString *const names[] = {@"AvenirNext-Medium", @"AvenirNext-DemiBold", @"AvenirNext-Heavy", @"AvenirNextCondensed-DemiBold", @"AvenirNextCondensed-Bold"};
    return [NSFont fontWithName:names[f] size:pt] ?: [NSFont systemFontOfSize:pt weight:f == F_HEAVY ? NSFontWeightHeavy : f == F_BODY ? NSFontWeightRegular : NSFontWeightBold];
}
static NSDictionary *attrs(int f, CGFloat pt, NSColor *c, CGFloat track, BOOL shadow, NSTextAlignment al)
{
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.alignment = al; ps.lineBreakMode = NSLineBreakByTruncatingTail;
    NSMutableDictionary *a = [@{NSFontAttributeName: face(f, pt), NSForegroundColorAttributeName: c, NSKernAttributeName: @(track),
                                NSParagraphStyleAttributeName: ps} mutableCopy];
    if (shadow) { NSShadow *s = [NSShadow new]; s.shadowColor = [NSColor colorWithWhite:0 alpha:0.8]; s.shadowOffset = NSMakeSize(0, -1); s.shadowBlurRadius = 2; a[NSShadowAttributeName] = s; }
    return a;
}
static CGFloat text_w(NSString *s, int f, CGFloat pt, CGFloat track) { return ceil([s sizeWithAttributes:attrs(f, pt, NSColor.whiteColor, track, NO, NSTextAlignmentLeft)].width); }
/* Text in r, centred on r's height. */
static void text(NSString *s, NSRect r, int f, CGFloat pt, NSColor *c, NSTextAlignment al, CGFloat track, BOOL shadow)
{
    if (!s.length) return;
    NSDictionary *a = attrs(f, pt, c, track, shadow, al); NSFont *fn = a[NSFontAttributeName];
    CGFloat lh = ceil(fn.ascender - fn.descender);
    [s drawInRect:NSMakeRect(r.origin.x, r.origin.y + (r.size.height - lh) / 2, r.size.width, lh + 2) withAttributes:a];
}
static void caps(NSString *s, NSRect r, int f, CGFloat pt, NSColor *c, NSTextAlignment al, CGFloat track, BOOL shadow)
{ text(s.uppercaseString, r, f, pt, c, al, track, shadow); }
static void fill(NSRect r, NSColor *c) { [c setFill]; NSRectFillUsingOperation(r, NSCompositingOperationSourceOver); }
/* A gradient of one colour's alpha: down (vertical) or across. */
static void grad(NSRect r, uint32_t c, int n, const CGFloat *at, const CGFloat *alpha, BOOL down)
{
    NSMutableArray *cs = [NSMutableArray array]; CGFloat loc[8];
    for (int i = 0; i < n; i++) { [cs addObject:rgb(c, alpha[i])]; loc[i] = at[i]; }
    [[[NSGradient alloc] initWithColors:cs atLocations:loc colorSpace:NSColorSpace.sRGBColorSpace] drawInRect:r angle:down ? 90 : 0];
}
static void chevron(CGFloat cx, CGFloat cy, BOOL right, CGFloat w, CGFloat h, NSColor *c)
{
    NSBezierPath *p = [NSBezierPath bezierPath]; p.lineWidth = 2; p.lineCapStyle = NSLineCapStyleRound; p.lineJoinStyle = NSLineJoinStyleRound;
    CGFloat x0 = cx - w / 2, x1 = cx + w / 2;
    if (right) { [p moveToPoint:NSMakePoint(x0, cy - h / 2)]; [p lineToPoint:NSMakePoint(x1, cy)]; [p lineToPoint:NSMakePoint(x0, cy + h / 2)]; }
    else { [p moveToPoint:NSMakePoint(x1, cy - h / 2)]; [p lineToPoint:NSMakePoint(x0, cy)]; [p lineToPoint:NSMakePoint(x1, cy + h / 2)]; }
    [c setStroke]; [p stroke];
}
/* A picture fitted into r, its aspect kept (never stretched), aligned left, right or centred. */
static NSRect picture(NSImage *img, NSRect r, NSTextAlignment al, CGFloat alpha)
{
    if (img.size.width < 2) return NSZeroRect;
    CGFloat s = MIN(r.size.width / img.size.width, r.size.height / img.size.height), w = img.size.width * s, h = img.size.height * s;
    CGFloat x = al == NSTextAlignmentLeft ? r.origin.x : al == NSTextAlignmentRight ? NSMaxX(r) - w : NSMidX(r) - w / 2;
    NSRect d = NSMakeRect(x, NSMidY(r) - h / 2, w, h);
    [img drawInRect:d fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:alpha respectFlipped:YES hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
    return d;
}
/* A picture covering r, its aspect kept: cropped, the crop at (fx, fy) of what is spare. */
static void cover(NSImage *img, NSRect r, CGFloat fx, CGFloat fy, CGFloat alpha)
{
    if (img.size.width < 2) return;
    CGFloat s = MAX(r.size.width / img.size.width, r.size.height / img.size.height), w = r.size.width / s, h = r.size.height / s;
    NSRect from = NSMakeRect((img.size.width - w) * fx, img.size.height - h - (img.size.height - h) * fy, w, h);   /* NSImage rows: bottom-up */
    [img drawInRect:r fromRect:from operation:NSCompositingOperationSourceOver fraction:alpha respectFlipped:YES hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
}

/* The key art: one picture up, a little larger than the window, drifting over its turn, then handed over to the next
 * with a crossfade; another game's comes in sliding. Core Animation layers, so it moves on the GPU and costs the
 * launcher nothing between hand-overs. A hero: image, zoom, fx, fy, dx, dy (launcher_games.c's LauncherHero). */
@interface TSHeroView : NSView
@property (nonatomic) BOOL still;                  /* a picture of the window (TS2_LAUNCHER_SHOT): drawn, not layered */
- (void)showHeroes:(NSArray<NSDictionary *> *)heroes slide:(NSInteger)dir;
@end
@implementation TSHeroView {
    NSArray<NSDictionary *> *_heroes; NSInteger _k; CALayer *_cur; NSTimer *_timer;
}
- (BOOL)isFlipped { return YES; }
- (instancetype)initWithFrame:(NSRect)f
{
    if ((self = [super initWithFrame:f])) { self.wantsLayer = YES; self.layer.backgroundColor = rgb(INK, 1).CGColor; self.layer.masksToBounds = YES; }
    return self;
}
/* Where a hero's picture sits, and how large, at a point d (0..1) of its turn. */
static NSRect hero_frame(NSDictionary *h, double d)
{
    NSImage *img = h[@"image"]; double zoom = [h[@"zoom"] doubleValue];
    double s = MAX(W / img.size.width, H / img.size.height) * zoom, w = img.size.width * s, hh = img.size.height * s;
    double ox = (w - W) * [h[@"fx"] doubleValue] + [h[@"dx"] doubleValue] * (d - 0.5);
    double oy = (hh - H) * [h[@"fy"] doubleValue] + [h[@"dy"] doubleValue] * (d - 0.5);
    return NSMakeRect(-ox, -oy, w, hh);
}
- (void)drawRect:(NSRect)dirty
{
    fill(self.bounds, rgb(INK, 1));
    if (!self.still || !_heroes.count) return;
    NSDictionary *h = _heroes[_k]; NSImage *img = h[@"image"];
    [img drawInRect:hero_frame(h, 0.5) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
}
- (CALayer *)layerFor:(NSDictionary *)h
{
    NSImage *img = h[@"image"];
    CGImageRef cg = [img CGImageForProposedRect:NULL context:nil hints:nil];
    CALayer *l = [CALayer layer]; l.contents = (__bridge id)cg; l.anchorPoint = CGPointZero;
    l.minificationFilter = kCAFilterTrilinear; l.magnificationFilter = kCAFilterLinear;
    NSRect a = hero_frame(h, 0), b = hero_frame(h, 1);
    l.bounds = CGRectMake(0, 0, a.size.width, a.size.height); l.position = b.origin;       /* where it ends */
    CABasicAnimation *drift = [CABasicAnimation animationWithKeyPath:@"position"];       /* over its whole turn */
    drift.fromValue = [NSValue valueWithPoint:a.origin]; drift.toValue = [NSValue valueWithPoint:b.origin];
    drift.duration = HOLD + FADE; drift.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [l addAnimation:drift forKey:@"drift"];
    return l;
}
- (void)handOver:(NSInteger)k slide:(NSInteger)dir
{
    if (self.still) { _k = k; self.needsDisplay = YES; return; }
    CALayer *old = _cur, *now = [self layerFor:_heroes[k]]; _k = k; _cur = now;
    double len = dir ? SWITCH : old ? FADE : 0;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    [self.layer addSublayer:now];
    if (len > 0) {
        CABasicAnimation *in = [CABasicAnimation animationWithKeyPath:@"opacity"];
        in.fromValue = @0; in.toValue = @1; in.duration = len; in.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [now addAnimation:in forKey:@"in"];
        if (dir) {                                                       /* the new game's slides in; the old one's out */
            CABasicAnimation *s = [CABasicAnimation animationWithKeyPath:@"position"]; s.additive = YES;
            s.fromValue = [NSValue valueWithPoint:NSMakePoint(dir * SLIDE, 0)]; s.toValue = [NSValue valueWithPoint:NSZeroPoint];
            s.duration = len; s.timingFunction = in.timingFunction; [now addAnimation:s forKey:@"slide"];
            if (old) {
                CABasicAnimation *o = [CABasicAnimation animationWithKeyPath:@"position"]; o.additive = YES;
                o.fromValue = [NSValue valueWithPoint:NSZeroPoint]; o.toValue = [NSValue valueWithPoint:NSMakePoint(-dir * SLIDE, 0)];
                o.duration = len; o.timingFunction = in.timingFunction; o.fillMode = kCAFillModeForwards; o.removedOnCompletion = NO;
                [old addAnimation:o forKey:@"slide"];
            }
        }
    }
    [CATransaction commit];
    if (old) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((len + 0.05) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [old removeFromSuperlayer]; });
}
- (void)showHeroes:(NSArray<NSDictionary *> *)heroes slide:(NSInteger)dir
{
    [_timer invalidate]; _timer = nil;
    _heroes = heroes;
    if (!heroes.count) { [_cur removeFromSuperlayer]; _cur = nil; self.needsDisplay = YES; return; }
    [self handOver:0 slide:dir];
    if (heroes.count > 1 && !self.still) {
        __weak TSHeroView *ws = self;
        _timer = [NSTimer scheduledTimerWithTimeInterval:HOLD repeats:YES block:^(NSTimer *t) {
            TSHeroView *s = ws; if (!s) return;
            [s handOver:(s->_k + 1) % (NSInteger)s->_heroes.count slide:0];
        }];
    }
}
@end

/* The menu, the panels and the extras over the key art. */
@interface TSLaunchView : NSView
@property NSArray<NSNumber *> *items;                    /* IT_* along the row */
@property NSInteger focus, hover, pressed, open, rowFocus;   /* open: a panel, or -1; rowFocus -1: its title-bar link */
@property NSArray<TSPanel *> *panels;
@property NSImage *logo, *otherLogo; @property NSString *gameName, *otherName, *cardName;
@property uint32_t accentRGB, washRGB;
@property (copy) NSString *(^caption)(NSInteger kind);
@property (copy) void (^onItem)(NSInteger kind); @property (copy) void (^onSwitch)(NSInteger dir); @property (copy) void (^onChange)(void);
/* the Extras: each {title, section, kind, target, picture (NSImage), about}; the folder; pictures for one without its own */
@property BOOL extrasOpen; @property NSArray<NSDictionary *> *extras; @property NSString *extrasDir; @property NSArray<NSImage *> *fallback;
@property NSInteger section, sel, top;
@property (copy) void (^onOpenExtra)(NSDictionary *e); @property (copy) void (^onExtrasFolder)(void);
@property double switchedAt;                               /* when the game was switched: its logo fades in */
/* Setting up an online server (Play Together's SET UP A SERVER): the page, the server's files (recompose
 * tools/online_server, in the app beside the launcher), and which command line was last copied. */
@property BOOL helpOpen; @property NSString *serverFolder; @property NSInteger copiedBox; @property double copiedAt;
/* Play Together's box under its rows (the launcher's linkInfo: heading, lines, body, share), and copying what it shows */
@property (copy) NSDictionary *(^linkInfo)(void); @property (copy) void (^onCopyShare)(void); @property NSRect shareRect;
@property NSMutableArray<NSDictionary *> *hintRects;       /* where the hints were drawn, and what a click on each does */
@property NSMutableArray<NSValue *> *cmdRects;             /* the setup page's command lines */
@end

@implementation TSLaunchView { double _bar, _barW; NSTimer *_anim; }
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }
- (NSColor *)accent { return rgb(self.accentRGB, 1); }
- (NSColor *)bright { return rgb(brighter(self.accentRGB), 1); }
- (NSArray<TSRow *> *)rows { return self.open >= 0 ? self.panels[self.open].rows : @[]; }
- (BOOL)rowCycles:(NSInteger)k { return self.rows[k].choices.count > 1 || self.rows[k].activate != nil; }
/* Redrawn while something moves (the focus sliding, a logo fading in), then left alone. */
- (void)animate
{
    self.needsDisplay = YES;
    if (_anim) return;
    __weak TSLaunchView *ws = self;
    _anim = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60 repeats:YES block:^(NSTimer *t) { ws.needsDisplay = YES; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        TSLaunchView *s = ws; if (!s) return; [s->_anim invalidate]; s->_anim = nil; s.needsDisplay = YES; });
}

// ------------------------------------------------ where things are
- (NSString *)itemName:(NSInteger)kind
{
    static NSString *const t[] = {@"PLAY", @"GRAPHICS", @"CONTROLS", @"PLAY TOGETHER", @"SAVES", @"EXTRAS", @"UPDATES", @"QUIT"};
    return t[kind];
}
- (NSRect)itemRect:(NSInteger)i
{
    CGFloat x = ROW_X;
    for (NSInteger k = 0; k < (NSInteger)self.items.count; k++) {
        NSInteger kind = self.items[k].integerValue; BOOL big = kind == IT_PLAY;
        CGFloat w = big ? text_w([self itemName:kind], F_HEAVY, 22, 6) : text_w([self itemName:kind], F_COND_BOLD, 14, 2);
        if (k == i) return NSMakeRect(x - 18, ROW_Y, w + 36, ROW_H);
        x += w + (big ? ROW_GAP + 18 : ROW_GAP);
    }
    return NSMakeRect(x, ROW_Y, 10, ROW_H);
}
- (CGFloat)switchTextW { return text_w(@"TAB  SWITCH GAME", F_DISPLAY, 9, 3); }
- (NSRect)switchRect { CGFloat tw = self.switchTextW; return NSMakeRect(W - 56 - tw - 18 - 150 - 8, ROW_Y - 74 - 6, tw + 18 + 150 + 16, 68); }
- (NSInteger)pitch
{
    NSInteger n = (NSInteger)self.rows.count, room = H - 96 - ROWS_Y - 48 - 40, p = n ? room / n : PITCH;
    return p >= PITCH ? PITCH : p < 36 ? 36 : p;
}
- (NSRect)rowRect:(NSInteger)k { NSInteger p = self.pitch; return NSMakeRect(PANEL_X, ROWS_Y + p * k, PANEL_W, p - 6); }
- (NSRect)rowArrow:(NSInteger)k right:(BOOL)right { NSRect r = [self rowRect:k]; return NSMakeRect(right ? NSMaxX(r) - 34 : NSMaxX(r) - 330, r.origin.y, 30, r.size.height); }
- (NSRect)linkRect { return NSMakeRect(PANEL_X - 8, 70, 190, 34); }
- (NSArray<NSDictionary *> *)shown
{
    if (!self.section) return self.extras;
    NSString *s = self.sections[self.section - 1];
    return [self.extras filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *e, id b) { return [e[@"section"] isEqual:s]; }]];
}
- (NSArray<NSString *> *)sections
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSDictionary *e in self.extras) if (![a containsObject:e[@"section"]] && a.count < 8) [a addObject:e[@"section"]];
    return a;
}
- (NSRect)sectionRect:(NSInteger)s
{
    CGFloat x = EX_X0; NSArray *secs = self.sections;
    for (NSInteger i = 0; i < s; i++) x += text_w([(i ? secs[i - 1] : @"ALL") uppercaseString], F_COND_BOLD, 11, 3) + 32;
    return NSMakeRect(x - 8, 140, text_w([(s ? secs[s - 1] : @"ALL") uppercaseString], F_COND_BOLD, 11, 3) + 24, 34);
}
- (NSRect)tileRect:(NSInteger)k
{
    NSInteger row = k / EX_COLS - self.top, col = k % EX_COLS;
    return NSMakeRect(EX_X0 + col * (EX_TW + EX_GAP), EX_Y0 + row * EX_PITCH, EX_TW, EX_TH);
}
- (NSInteger)hit:(NSPoint)p
{
    for (NSDictionary *h in self.hintRects) if (NSPointInRect(p, [h[@"rect"] rectValue])) return [h[@"code"] integerValue];
    if (self.helpOpen) {
        for (NSInteger k = 0; k < (NSInteger)self.cmdRects.count; k++) if (NSPointInRect(p, [self.cmdRects[k] rectValue])) return HIT_CMD + k;
        return HIT_NONE;
    }
    if (self.extrasOpen) {
        for (NSInteger s = 0; s <= (NSInteger)self.sections.count; s++) if (NSPointInRect(p, [self sectionRect:s])) return HIT_SECTION + s;
        NSInteger n = (NSInteger)self.shown.count;
        for (NSInteger i = self.top * EX_COLS; i < n && i < (self.top + EX_ROWS) * EX_COLS; i++) if (NSPointInRect(p, [self tileRect:i])) return HIT_TILE + i;
        return HIT_NONE;
    }
    if (self.open >= 0) {
        if (self.panels[self.open].linkTitle && NSPointInRect(p, self.linkRect)) return HIT_PLINK;
        if (NSPointInRect(p, self.shareRect)) return HIT_SHARE;
        for (NSInteger k = 0; k < (NSInteger)self.rows.count; k++) {
            if (![self rowCycles:k]) continue;
            if (self.rows[k].choices.count > 1 && NSPointInRect(p, [self rowArrow:k right:NO])) return HIT_ROW + 10 * k;
            if (self.rows[k].choices.count > 1 && NSPointInRect(p, [self rowArrow:k right:YES])) return HIT_ROW + 10 * k + 2;
            if (NSPointInRect(p, NSInsetRect([self rowRect:k], -10, 0))) return HIT_ROW + 10 * k + 1;
        }
        return HIT_NONE;
    }
    for (NSInteger i = 0; i < (NSInteger)self.items.count; i++) if (NSPointInRect(p, [self itemRect:i])) return HIT_ITEM + i;
    if (self.otherName && NSPointInRect(p, self.switchRect)) return HIT_SWITCH;
    return HIT_NONE;
}

// ------------------------------------------------ input
- (void)updateTrackingAreas
{
    for (NSTrackingArea *t in self.trackingAreas) [self removeTrackingArea:t];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseMoved:(NSEvent *)e
{
    NSInteger h = [self hit:[self convertPoint:e.locationInWindow fromView:nil]];
    if (h == self.hover) return;
    self.hover = h;
    if (!self.extrasOpen && self.open < 0 && h >= HIT_ITEM && h < HIT_ROW) { self.focus = h - HIT_ITEM; [self animate]; }   /* the focus follows the pointer */
    self.needsDisplay = YES;
}
- (void)mouseExited:(NSEvent *)e { self.hover = HIT_NONE; self.needsDisplay = YES; }
- (void)mouseDown:(NSEvent *)e
{
    NSInteger h = [self hit:[self convertPoint:e.locationInWindow fromView:nil]];
    if (h >= HIT_TILE && e.clickCount == 2) { self.sel = h - HIT_TILE; [self openSelected]; return; }   /* double-click: open it */
    self.pressed = h; self.needsDisplay = YES;
}
- (void)mouseUp:(NSEvent *)e
{
    NSInteger h = [self hit:[self convertPoint:e.locationInWindow fromView:nil]], p = self.pressed; self.pressed = HIT_NONE; self.needsDisplay = YES;
    if (h != p || h == HIT_NONE) return;
    if (h == HIT_BACK) { [self back]; return; }
    if (h == HIT_QUIT) { if (self.onItem) self.onItem(IT_QUIT); return; }
    if (h >= HIT_CMD) { [self copyCommand:h - HIT_CMD]; return; }
    if (h == HIT_SHARE) { if (self.onCopyShare) self.onCopyShare(); return; }
    if (h == HIT_PRICES) { [self openPrices]; return; }
    if (h == HIT_OPEN) { if (self.helpOpen) [self copyCommand:0]; else if (self.extrasOpen) [self openSelected]; else [self activate]; return; }
    if (h == HIT_FOLDER) { if (self.helpOpen) [self openServerFolder]; else if (self.onExtrasFolder) self.onExtrasFolder(); return; }
    if (h == HIT_SWITCH) { if (self.onSwitch) self.onSwitch(1); return; }
    if (h == HIT_PLINK) { [self openPanel:self.panels[self.open].linkPanel]; return; }
    if (h >= HIT_TILE) { self.sel = h - HIT_TILE; return; }
    if (h >= HIT_SECTION) { self.section = h - HIT_SECTION; self.sel = self.top = 0; return; }
    if (h >= HIT_ROW) { NSInteger k = (h - HIT_ROW) / 10; self.rowFocus = k; [self stepRow:k by:(h - HIT_ROW) % 10 == 0 ? -1 : 1]; return; }
    if (h >= HIT_ITEM) { self.focus = h - HIT_ITEM; [self activate]; }
}
- (void)activate { if (self.onItem) self.onItem(self.items[self.focus].integerValue); }
- (void)openPanel:(NSInteger)i
{
    if (i == -2) { self.helpOpen = YES; self.hover = HIT_NONE; self.needsDisplay = YES; return; }   /* the online server's page */
    self.open = i; self.hover = HIT_NONE; self.rowFocus = 0;
    while (self.rowFocus < (NSInteger)self.rows.count - 1 && ![self rowCycles:self.rowFocus]) self.rowFocus++;
    self.needsDisplay = YES;
}
- (void)back
{
    if (self.helpOpen) { self.helpOpen = NO; self.hover = HIT_NONE; self.needsDisplay = YES; return; }   /* back to Play Together */
    [self backHome];
}
- (void)backHome { self.open = -1; self.extrasOpen = NO; self.hover = HIT_NONE; self.needsDisplay = YES; }
- (void)stepRow:(NSInteger)k by:(NSInteger)dir
{
    TSRow *t = self.rows[k]; NSInteger n = (NSInteger)t.choices.count;
    if (t.activate) { t.activate(); self.needsDisplay = YES; return; }        /* e.g. typing the host's address */
    if (n < 2) return;
    t.index = (t.index + dir + n) % n;
    self.needsDisplay = YES; if (self.onChange) self.onChange();
}
- (void)moveRowFocus:(NSInteger)dir
{
    NSInteger n = (NSInteger)self.rows.count, first = 0;
    while (first < n - 1 && ![self rowCycles:first]) first++;
    if (self.panels[self.open].linkTitle) {                             /* up from the first row: the title bar's link */
        if (self.rowFocus == -1) { if (dir > 0) self.rowFocus = first; self.needsDisplay = YES; return; }
        if (dir < 0 && self.rowFocus == first) { self.rowFocus = -1; self.needsDisplay = YES; return; }
    }
    for (NSInteger i = 0; i < n; i++) { self.rowFocus = (self.rowFocus + dir + n) % n; if ([self rowCycles:self.rowFocus]) break; }
    self.needsDisplay = YES;
}
- (void)openSelected { NSArray *s = self.shown; if (self.sel >= 0 && self.sel < (NSInteger)s.count && self.onOpenExtra) self.onOpenExtra(s[self.sel]); }
- (void)keyDown:(NSEvent *)e
{
    unsigned short c = e.keyCode; BOOL shift = (e.modifierFlags & NSEventModifierFlagShift) != 0;
    NSString *chars = e.charactersIgnoringModifiers.lowercaseString;
    if (self.helpOpen) {
        if (c == 0x35) { [self back]; return; }                                         /* Escape: back to Play Together */
        if (c == 0x24 || c == 0x4c) { [self copyCommand:0]; return; }                    /* Return: the install line */
        if ([chars isEqual:@"f"]) { [self openServerFolder]; return; }
        if ([chars isEqual:@"p"]) { [self openPrices]; return; }
        [super keyDown:e]; return;
    }
    if (self.extrasOpen) {
        NSInteger n = (NSInteger)self.shown.count, ns = (NSInteger)self.sections.count + 1;
        switch (c) {
        case 0x35: [self back]; return;                                                   /* Escape */
        case 0x24: case 0x4c: [self openSelected]; return;                                /* Return */
        case 0x30: self.section = (self.section + (shift ? -1 : 1) + ns) % ns; self.sel = self.top = 0; self.needsDisplay = YES; return;   /* Tab: the sections */
        case 0x7b: if (self.sel > 0) self.sel--; self.needsDisplay = YES; return;
        case 0x7c: if (self.sel + 1 < n) self.sel++; self.needsDisplay = YES; return;
        case 0x7e: if (self.sel >= EX_COLS) self.sel -= EX_COLS; self.needsDisplay = YES; return;
        case 0x7d: if (self.sel + EX_COLS < n) self.sel += EX_COLS; else if (n) self.sel = n - 1; self.needsDisplay = YES; return;
        }
        if ([chars isEqual:@"o"]) { if (self.onExtrasFolder) self.onExtrasFolder(); return; }
        [super keyDown:e]; return;
    }
    if (self.open == 2 && (e.modifierFlags & NSEventModifierFlagCommand) && [chars isEqual:@"c"]) { if (self.onCopyShare) self.onCopyShare(); return; }
    if (self.open >= 0) {
        switch (c) {
        case 0x24: case 0x4c: case 0x31: case 0x7b: case 0x7c:
            if (self.rowFocus == -1) { [self openPanel:self.panels[self.open].linkPanel]; return; }
            if (c == 0x7b) { [self stepRow:self.rowFocus by:-1]; return; }
            if (c == 0x7c) { [self stepRow:self.rowFocus by:1]; return; }
            if (self.rows[self.rowFocus].activate) { [self stepRow:self.rowFocus by:1]; return; }
            if (c == 0x31) break;
            [self back]; return;                                                         /* Return: back */
        case 0x35: [self back]; return;
        case 0x7e: [self moveRowFocus:-1]; return;
        case 0x7d: [self moveRowFocus:1]; return;
        case 0x30: [self moveRowFocus:shift ? -1 : 1]; return;
        }
        [super keyDown:e]; return;
    }
    NSInteger n = (NSInteger)self.items.count;
    switch (c) {
    case 0x24: case 0x4c: case 0x31: [self activate]; return;                               /* Return, Space */
    case 0x35: if (self.onItem) self.onItem(IT_QUIT); return;                              /* Escape */
    case 0x7b: case 0x7e: self.focus = (self.focus + n - 1) % n; [self animate]; return;   /* left / up */
    case 0x7c: case 0x7d: self.focus = (self.focus + 1) % n; [self animate]; return;       /* right / down */
    case 0x30: if (self.onSwitch) self.onSwitch(shift ? -1 : 1); return;                   /* Tab: the other game */
    }
    [super keyDown:e];
}

// ------------------------------------------------ drawing
/* The hints at the bottom right: each [key, what it does, its hit code]. */
- (void)hints:(NSArray<NSArray *> *)hs
{
    self.hintRects = [NSMutableArray array];
    CGFloat x = W - 64;
    for (NSInteger i = (NSInteger)hs.count - 1; i >= 0; i--) {
        NSString *key = hs[i][0], *label = hs[i][1]; NSInteger code = [hs[i][2] integerValue];
        BOOL hot = code != HIT_NONE && self.hover == code;
        CGFloat lw = text_w(label, F_DISPLAY, 11, 0) + 8, kw = text_w(key.uppercaseString, F_DISPLAY, 10, 1) + 4;
        NSRect lr = NSMakeRect(x - lw, H - 50, lw, 28), kr = NSMakeRect(lr.origin.x - 8 - kw, H - 50, kw, 28);
        text(label, lr, F_DISPLAY, 11, hot ? NSColor.whiteColor : rgb(0xD2DEF0, 1), NSTextAlignmentLeft, 0, YES);
        caps(key, kr, F_DISPLAY, 10, hot ? NSColor.whiteColor : self.accent, NSTextAlignmentRight, 1, YES);
        if (code != HIT_NONE) [self.hintRects addObject:@{@"rect": [NSValue valueWithRect:NSMakeRect(kr.origin.x - 4, kr.origin.y - 4, NSMaxX(lr) - kr.origin.x + 8, 36)], @"code": @(code)}];
        x = kr.origin.x - 30;
    }
}
/* Ink washed in from the right (under a panel), down from the top and up from the bottom. */
- (void)scrimsFrom:(CGFloat)from strength:(CGFloat)s
{
    CGFloat at3[3] = {0, 0.5, 1}, a3[3] = {0, s * 0.78, s}, at2[2] = {0, 1}, top[2] = {0.55, 0}, bot[2] = {0, 0.86};
    grad(NSMakeRect(from, 0, W - from, H), INK, 3, at3, a3, NO);
    grad(NSMakeRect(0, 0, W, 96), INK, 2, at2, top, YES);
    grad(NSMakeRect(0, H - 150, W, 150), INK, 2, at2, bot, YES);
}
- (void)drawRect:(NSRect)dirty
{
    if (self.helpOpen) [self drawHelp];
    else if (self.extrasOpen) [self drawExtras];
    else if (self.open >= 0) [self drawPanel];
    else [self drawHome];
}
- (void)drawHome
{
    NSInteger n = (NSInteger)self.items.count;
    if (self.focus >= n) self.focus = n - 1;
    if (self.focus < 0) self.focus = 0;
    {   /* ink up from the bottom for the menu, darker at its left; a little at the top */
        CGFloat at3[3] = {0, 0.45, 1}, a3[3] = {0, 0.72, 0.95}, at2[2] = {0, 1}, l2[2] = {0.55, 0}, top[2] = {0.5, 0};
        grad(NSMakeRect(0, H - 320, W, 320), INK, 3, at3, a3, YES);
        for (int k = 0; k < 20; k++) {                                    /* the left's extra, fading in downward: no edge */
            double t = (k + 0.5) / 20.0; l2[0] = 0.55 * t * t;
            grad(NSMakeRect(0, H - 320 + k * 16, 780, 16), INK, 2, at2, l2, NO);
        }
        grad(NSMakeRect(0, 0, W, 70), INK, 2, at2, top, YES);
    }
    double la = ease((now_s() - self.switchedAt) / 0.5);                 /* a switched-to game's logo fades in */
    if (self.logo.size.width > 2) {
        CGFloat h = MIN(170, 430 * self.logo.size.height / self.logo.size.width);
        picture(self.logo, NSMakeRect(ROW_X - 6, ROW_Y - 14 - h, 430, h), NSTextAlignmentLeft, la);
    } else {
        caps(self.gameName, NSMakeRect(ROW_X, ROW_Y - 70, 1000, 56), F_HEAVY, 24, rgb(0xEBF0FA, la), NSTextAlignmentLeft, 4, YES);
    }
    caps(@"TIMESLIP" DOT @"NATIVE FOR APPLE SILICON" DOT @"RECOMPILED FROM YOUR XBOX DISC", NSMakeRect(24, 16, 900, 18), F_DISPLAY, 8, rgb(0xA4B2CA, 1), NSTextAlignmentLeft, 3, YES);

    /* the focus: a block of the game's colour that slides to its item */
    NSRect r = [self itemRect:self.focus];
    if (_barW <= 0) { _bar = r.origin.x; _barW = r.size.width; }
    _bar += (r.origin.x - _bar) * 0.34; _barW += (r.size.width - _barW) * 0.34;
    if (fabs(_bar - r.origin.x) < 0.5) _bar = r.origin.x;
    if (fabs(_barW - r.size.width) < 0.5) _barW = r.size.width;
    CGFloat at[2] = {0, 1}, a[2] = {0.92, 0.78};
    grad(NSMakeRect(round(_bar), r.origin.y, round(_barW), r.size.height), self.washRGB, 2, at, a, YES);
    fill(NSMakeRect(round(_bar), NSMaxY(r) - 3, round(_barW), 3), self.bright);
    for (NSInteger i = 0; i < n; i++) {
        NSInteger kind = self.items[i].integerValue; BOOL on = i == self.focus, big = kind == IT_PLAY; NSRect ir = [self itemRect:i];
        if (big && !on) fill(ir, rgb(self.washRGB, 0.34));                       /* Play stands out unfocused too */
        if (big) caps([self itemName:kind], ir, F_HEAVY, 22, NSColor.whiteColor, NSTextAlignmentCenter, 6, YES);
        else caps([self itemName:kind], ir, F_COND_BOLD, 14, on ? NSColor.whiteColor : rgb(0xC6D0E2, 1), NSTextAlignmentCenter, 2, YES);
    }
    NSString *cap = self.caption ? self.caption(self.items[self.focus].integerValue) : nil;
    caps(cap, NSMakeRect(ROW_X, H - 54, 760, 28), F_COND, 10, self.bright, NSTextAlignmentLeft, 2, YES);

    if (self.otherName) {                                                /* the other game, over the row's right end */
        BOOL hot = self.hover == HIT_SWITCH; CGFloat tw = self.switchTextW;
        NSRect lr = NSMakeRect(W - 56 - tw - 18 - 150, ROW_Y - 74, 150, 56);
        if (self.otherLogo.size.width > 2) picture(self.otherLogo, lr, NSTextAlignmentRight, hot ? 1.0 : 0.75);
        else caps(self.otherName, NSMakeRect(lr.origin.x - 80, lr.origin.y, lr.size.width + 80, lr.size.height), F_HEAVY, 10, hot ? NSColor.whiteColor : rgb(0xB4C0D4, 1), NSTextAlignmentRight, 2, YES);
        caps(@"TAB  SWITCH GAME", NSMakeRect(W - 56 - tw, lr.origin.y, tw, lr.size.height), F_DISPLAY, 9, hot ? NSColor.whiteColor : rgb(0xA4B2CA, 1), NSTextAlignmentRight, 3, YES);
    }
    [self hints:@[@[@"ENTER", @"Select", @(HIT_OPEN)], @[@"ESC", @"Quit", @(HIT_QUIT)]]];
    if (_bar != r.origin.x || _barW != r.size.width || la < 1) [self animate];
}
- (void)drawPanel
{
    TSPanel *pn = self.panels[self.open];
    fill(self.bounds, rgb(INK, 0.22));
    [self scrimsFrom:260 strength:0.95];
    caps(pn.title, NSMakeRect(ROW_R - 600, 26, 600, 44), F_HEAVY, 28, NSColor.whiteColor, NSTextAlignmentRight, 7, YES);
    caps([@"FOR " stringByAppendingString:self.cardName ?: @""], NSMakeRect(ROW_R - 600, 74, 600, 20), F_DISPLAY, 9, self.accent, NSTextAlignmentRight, 4, YES);
    if (pn.linkTitle) {                                                  /* ADVANCED ›, or ‹ GRAPHICS back */
        NSRect a = self.linkRect; BOOL back = pn.linkLeft, foc = self.rowFocus == -1, hot = self.hover == HIT_PLINK;
        if (foc) { CGFloat at[2] = {0, 1}, al[2] = {0.66, 0}; grad(a, self.washRGB, 2, at, al, NO); fill(NSMakeRect(a.origin.x - 4, a.origin.y, 4, a.size.height), self.bright); }
        chevron(back ? a.origin.x + 12 : a.origin.x + text_w(pn.linkTitle, F_COND_BOLD, 10, 3) + 22, NSMidY(a), !back, 5, 10, hot || foc ? NSColor.whiteColor : self.accent);
        caps(pn.linkTitle, NSMakeRect(back ? a.origin.x + 26 : a.origin.x + 8, a.origin.y, a.size.width - 34, a.size.height), F_COND_BOLD, 10,
             hot || foc ? NSColor.whiteColor : rgb(0xBFCADC, 1), NSTextAlignmentLeft, 3, YES);
    }
    NSInteger n = (NSInteger)self.rows.count, p = self.pitch;
    for (NSInteger k = 0; k < n; k++) {
        TSRow *t = self.rows[k]; NSRect rr = [self rowRect:k]; NSDictionary *c = t.choices[t.index];
        BOOL cycles = [self rowCycles:k], foc = cycles && k == self.rowFocus, arrows = cycles && !t.activate && t.choices.count > 1;
        if (foc) { CGFloat at[2] = {0, 1}, al[2] = {0, 0.66}; grad(NSMakeRect(rr.origin.x - 40, rr.origin.y - 2, rr.size.width + 80, rr.size.height + 4), self.washRGB, 2, at, al, NO);
                   fill(NSMakeRect(NSMaxX(rr) + 36, rr.origin.y - 2, 4, rr.size.height + 4), self.bright); }
        if (k + 1 < n) fill(NSMakeRect(rr.origin.x, NSMaxY(rr) + 2, rr.size.width, 1), [NSColor colorWithWhite:1 alpha:0.07]);
        caps(t.title, NSMakeRect(rr.origin.x + 2, rr.origin.y, 300, rr.size.height), F_COND_BOLD, 13, foc ? NSColor.whiteColor : cycles ? rgb(0xBFCADC, 1) : rgb(0x8E9CB4, 1), NSTextAlignmentLeft, 2, YES);
        NSString *val = t.summary ? t.summary() : c[@"label"];
        if (arrows) {
            text(val, NSMakeRect(NSMaxX(rr) - 300, rr.origin.y, 262, rr.size.height), F_COND, 13, rgb(0xE6ECF6, 1), NSTextAlignmentCenter, 0, YES);
            chevron(NSMaxX(rr) - 315, NSMidY(rr), NO, 7, 13, foc || self.hover == HIT_ROW + 10 * k ? NSColor.whiteColor : self.accent);
            chevron(NSMaxX(rr) - 19, NSMidY(rr), YES, 7, 13, foc || self.hover == HIT_ROW + 10 * k + 2 ? NSColor.whiteColor : self.accent);
        } else {                                                         /* a value to read, or one to type: at the right */
            BOOL empty = !val.length && t.placeholder;
            text(empty ? t.placeholder : val, NSMakeRect(rr.origin.x + 230, rr.origin.y, rr.size.width - 238, rr.size.height), F_COND, 13,
                 empty ? rgb(0x7C8AA4, 1) : t.activate ? (foc ? NSColor.whiteColor : self.bright) : rgb(0xE6ECF6, 1), NSTextAlignmentRight, 0, YES);
        }
    }
    /* the focused row's help, then the panel's own note */
    CGFloat y = ROWS_Y + n * p + 8;
    NSString *help = self.rowFocus >= 0 && self.rowFocus < n ? self.rows[self.rowFocus].choices[self.rows[self.rowFocus].index][@"note"] : nil;
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.lineBreakMode = NSLineBreakByWordWrapping;
    if (help.length) [help drawInRect:NSMakeRect(PANEL_X + 2, y, PANEL_W - 4, 40) withAttributes:@{NSFontAttributeName: face(F_BODY, 11), NSForegroundColorAttributeName: rgb(0x9AA8C0, 1), NSParagraphStyleAttributeName: ps}];
    if (pn.footnote.length) [pn.footnote drawInRect:NSMakeRect(PANEL_X + 2, y + 40, PANEL_W - 4, 40) withAttributes:@{NSFontAttributeName: face(F_BODY, 10.5), NSForegroundColorAttributeName: rgb(0x7C8AA4, 1), NSParagraphStyleAttributeName: ps}];
    self.shareRect = NSZeroRect;
    NSDictionary *info = self.open == 2 && self.linkInfo ? self.linkInfo() : nil;
    if (info) {                                                          /* draw_link's box: what to tell friends, or what to do */
        NSArray *lines = info[@"lines"];
        CGFloat bh = MIN(H - 96 - (y + 48), 46 + 26.0 * lines.count + 70);
        NSRect box = NSMakeRect(PANEL_X - 10, y + 48, PANEL_W + 20, bh);
        BOOL hot = [info[@"share"] boolValue] && self.hover == HIT_SHARE;
        fill(box, [NSColor colorWithWhite:0 alpha:hot ? 0.45 : 0.3]); fill(NSMakeRect(box.origin.x, box.origin.y, 3, box.size.height), self.accent);
        caps(info[@"heading"], NSMakeRect(box.origin.x + 16, box.origin.y + 12, box.size.width - 32, 20), F_DISPLAY, 9, self.accent, NSTextAlignmentLeft, 3, YES);
        CGFloat ly = box.origin.y + 40;
        for (NSArray *l in lines) {
            text(l[0], NSMakeRect(box.origin.x + 16, ly, box.size.width - 32, 22), F_BODY, 12, [l[1] boolValue] ? rgb(0xEBF0FA, 1) : rgb(0x8E9CB4, 1), NSTextAlignmentLeft, 0, NO);
            ly += 26;
        }
        [info[@"body"] drawInRect:NSMakeRect(box.origin.x + 16, ly + 4, box.size.width - 32, NSMaxY(box) - ly - 8)
                   withAttributes:@{NSFontAttributeName: face(F_BODY, 11), NSForegroundColorAttributeName: rgb(0x9AA8C0, 1), NSParagraphStyleAttributeName: ps}];
        if ([info[@"share"] boolValue]) self.shareRect = box;
    }
    [self hints:@[@[@"← →", @"Change", @(HIT_NONE)], @[@"ESC", @"Back", @(HIT_BACK)]]];
}
// ------------------------------------------------ setting up an online server
/* Fly.io's own commands (fly.io/docs/flyctl/install): 0 installs flyctl, 1 runs the setup from the server's folder. */
- (NSString *)command:(NSInteger)k
{
    if (k == 0) return @"curl -L https://fly.io/install.sh | sh";
    return [NSString stringWithFormat:@"sh \"%@/deploy.sh\"", self.serverFolder ?: @"online_server"];
}
- (void)copyCommand:(NSInteger)k
{
    [NSPasteboard.generalPasteboard clearContents]; [NSPasteboard.generalPasteboard setString:[self command:k] forType:NSPasteboardTypeString];
    self.copiedBox = k; self.copiedAt = now_s(); self.needsDisplay = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ self.needsDisplay = YES; });
}
- (void)openServerFolder { if (self.serverFolder) [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:self.serverFolder isDirectory:YES]]; }
- (void)openPrices { [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://fly.io/docs/about/pricing/"]]; }
/* The page, as the Windows launcher's: five steps, two of them a line to type, which a click copies. */
- (void)drawHelp
{
    fill(self.bounds, rgb(INK, 0.5)); fill(self.bounds, rgb(INK, 0.45));
    caps(@"SET UP AN ONLINE SERVER", NSMakeRect(EX_X0, 30, 900, 50), F_HEAVY, 26, NSColor.whiteColor, NSTextAlignmentLeft, 6, YES);
    caps(@"ON FLY.IO" DOT @"ONCE, BY ONE OF YOU", NSMakeRect(EX_X0, 80, 900, 20), F_DISPLAY, 9, self.accent, NSTextAlignmentLeft, 4, YES);
    if (self.logo.size.width > 2) picture(self.logo, NSMakeRect(ROW_R - 300 + 8, 22, 300, 96), NSTextAlignmentRight, 0.9);
    NSString *shown = self.serverFolder ?: @"the online_server folder of the game's source";
    NSArray *head = @[@"WHAT IT IS", @"A FLY.IO ACCOUNT, ON PAY AS YOU GO", @"INSTALL FLYCTL", @"RUN THE SETUP", @"CONNECT"];
    NSArray *body = @[
        @"One server every copy connects to, for System Link and online co-op: nobody opens a port on their router. One of you runs it and shares its address. At Fly's prices it costs about $4.20 a month: a small machine, $2.19, and the dedicated IPv4 address UDP needs, $2.",
        @"Sign up at fly.io and add a card. Then, on Fly's dashboard, Billing, switch to Pay As You Go: Fly's Free plan has no dedicated IPv4 addresses, and a game's traffic (UDP) needs one. P shows Fly's prices.",
        @"Fly's command line. In Terminal, run this (Return, or a click on it, copies it):",
        [NSString stringWithFormat:@"In a new Terminal window, run this (a click copies it). It signs you in to Fly, asks a name and the region nearest you, and makes and starts the server; at the end it prints its address, like name.fly.dev. Its files: %@ (F opens the folder).", shown],
        @"Back here: Connect, Through an online server; Server Address, what it printed; Session Code, any word of four letters or more. Everyone playing types the same two. To remove the server, and its cost: flyctl apps destroy, with its name."];
    const int lines[5] = {2, 2, 1, 2, 2}, box[5] = {-1, -1, 0, 1, -1};
    CGFloat y = 112, wide = W - EX_X0 * 2 - 44;
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.lineBreakMode = NSLineBreakByWordWrapping;
    self.cmdRects = [NSMutableArray array];
    for (int i = 0; i < 5; i++) {
        text([NSString stringWithFormat:@"%d", i + 1], NSMakeRect(EX_X0, y, 40, 30), F_HEAVY, 20, self.bright, NSTextAlignmentLeft, 0, YES);
        caps(head[i], NSMakeRect(EX_X0 + 44, y + 2, 900, 22), F_COND_BOLD, 12, NSColor.whiteColor, NSTextAlignmentLeft, 3, YES);
        [body[i] drawInRect:NSMakeRect(EX_X0 + 44, y + 28, wide, 20 * lines[i] + 4)
             withAttributes:@{NSFontAttributeName: face(F_BODY, 12), NSForegroundColorAttributeName: rgb(0xC6D0E2, 1), NSParagraphStyleAttributeName: ps}];
        y += 28 + 20 * lines[i] + 8;
        if (box[i] >= 0) {
            NSInteger k = box[i]; BOOL hot = self.hover == HIT_CMD + k, copied = self.copiedBox == k && now_s() - self.copiedAt < 1.5;
            NSRect c = NSMakeRect(EX_X0 + 44, y, wide, 30); [self.cmdRects addObject:[NSValue valueWithRect:c]];
            NSString *cmd = [self command:k]; CGFloat room = wide - 14 - 80, pt = 12;
            while (pt > 9 && text_w(cmd, F_BODY, pt, 0) > room) pt -= 0.5;              /* a long folder: smaller, to show it whole */
            fill(c, [NSColor colorWithWhite:0 alpha:hot ? 0.7 : 0.55]); fill(NSMakeRect(c.origin.x, y, 3, 30), self.bright);
            text(cmd, NSMakeRect(c.origin.x + 14, y, room, 30), F_BODY, pt, rgb(0xEAF2FF, 1), NSTextAlignmentLeft, 0, NO);
            if (copied || hot) caps(copied ? @"COPIED" : @"COPY", NSMakeRect(NSMaxX(c) - 80, y, 70, 30), F_COND_BOLD, 9, copied ? self.bright : rgb(0xBFCADC, 1), NSTextAlignmentRight, 3, YES);
            y += 36;
        }
        y += 10;
    }
    [self hints:@[@[@"ENTER", @"Copy the install line", @(HIT_OPEN)], @[@"F", @"Server folder", @(HIT_FOLDER)], @[@"P", @"Fly's prices", @(HIT_PRICES)], @[@"ESC", @"Back", @(HIT_BACK)]]];
}
- (void)drawExtras
{
    NSArray<NSDictionary *> *shown = self.shown; NSInteger n = (NSInteger)shown.count; NSArray *secs = self.sections;
    if (self.sel >= n) self.sel = n ? n - 1 : 0;
    fill(self.bounds, rgb(INK, 0.5)); fill(self.bounds, rgb(INK, 0.3));
    [self scrimsFrom:0 strength:0.5];
    caps(@"EXTRAS", NSMakeRect(EX_X0, 30, 600, 50), F_HEAVY, 28, NSColor.whiteColor, NSTextAlignmentLeft, 7, YES);
    caps([NSString stringWithFormat:@"%@%@MANUALS, VIDEOS AND PICTURES", self.cardName ?: @"", DOT], NSMakeRect(EX_X0, 82, 900, 20), F_DISPLAY, 9, self.accent, NSTextAlignmentLeft, 4, YES);
    if (self.logo.size.width > 2) picture(self.logo, NSMakeRect(ROW_R - 300 + 8, 22, 300, 96), NSTextAlignmentRight, 0.9);
    if (!self.extras.count) {
        text(@"Nothing here yet.", NSMakeRect(EX_X0, 190, 1000, 40), F_DISPLAY, 20, rgb(0xE6ECF6, 1), NSTextAlignmentLeft, 0, YES);
        text(@"Manuals (PDF), videos, pictures and links (.url, .webloc) put in this game's Extras folder show up here:", NSMakeRect(EX_X0, 240, 1100, 26), F_BODY, 12, rgb(0xAEBBD0, 1), NSTextAlignmentLeft, 0, NO);
        text([self.extrasDir stringByAbbreviatingWithTildeInPath], NSMakeRect(EX_X0, 274, 1150, 28), F_BODY, 13, self.bright, NSTextAlignmentLeft, 0, YES);
        text(@"An extras.json beside them can name, order and sort them, give each a picture, and add links.", NSMakeRect(EX_X0, 312, 1100, 26), F_BODY, 12, rgb(0xAEBBD0, 1), NSTextAlignmentLeft, 0, NO);
        [self hints:@[@[@"O", @"Open folder", @(HIT_FOLDER)], @[@"ESC", @"Back", @(HIT_BACK)]]];
        return;
    }
    for (NSInteger s = 0; s <= (NSInteger)secs.count; s++) {             /* the sections: ALL, then each one found */
        NSRect sr = [self sectionRect:s]; BOOL on = s == self.section, hot = self.hover == HIT_SECTION + s;
        caps(s ? secs[s - 1] : @"ALL", NSMakeRect(sr.origin.x + 8, sr.origin.y, sr.size.width, sr.size.height), F_COND_BOLD, 11, on || hot ? NSColor.whiteColor : rgb(0x96A6C0, 1), NSTextAlignmentLeft, 3, YES);
        if (on) fill(NSMakeRect(sr.origin.x + 8, NSMaxY(sr) - 4, sr.size.width - 24, 3), self.bright);
    }
    if (self.sel / EX_COLS < self.top) self.top = self.sel / EX_COLS;
    if (self.sel / EX_COLS >= self.top + EX_ROWS) self.top = self.sel / EX_COLS - EX_ROWS + 1;
    for (NSInteger i = self.top * EX_COLS; i < n && i < (self.top + EX_ROWS) * EX_COLS; i++) {
        NSDictionary *e = shown[i]; NSRect tr = [self tileRect:i]; BOOL on = i == self.sel, hot = self.hover == HIT_TILE + i;
        fill(tr, [NSColor colorWithWhite:0 alpha:0.6]);
        NSImage *pic = e[@"picture"]; BOOL own = pic != nil;
        if (!pic && self.fallback.count) pic = self.fallback[(NSUInteger)i % self.fallback.count];   /* one without a picture: the key art */
        [NSGraphicsContext saveGraphicsState]; NSRectClip(tr);
        cover(pic, tr, 0.5, own ? 0.5 : 0.42, on ? 1.0 : hot ? 0.9 : 0.62);
        [NSGraphicsContext restoreGraphicsState];
        if (on) { [self.bright setStroke]; NSBezierPath *b = [NSBezierPath bezierPathWithRect:NSInsetRect(tr, -1.5, -1.5)]; b.lineWidth = 3; [b stroke]; }
        caps(e[@"title"], NSMakeRect(tr.origin.x, NSMaxY(tr) + 8, tr.size.width, 24), F_COND_BOLD, 13, on ? NSColor.whiteColor : rgb(0xBFCADC, 1), NSTextAlignmentLeft, 2, YES);
        caps([NSString stringWithFormat:@"%@%@%@", e[@"section"], DOT, e[@"kind"]], NSMakeRect(tr.origin.x, NSMaxY(tr) + 32, tr.size.width, 18), F_DISPLAY, 8, on ? self.bright : rgb(0x8494AE, 1), NSTextAlignmentLeft, 2, YES);
    }
    if ((self.top + EX_ROWS) * EX_COLS < n) chevron(W / 2.0, EX_Y0 + EX_ROWS * EX_PITCH - 8, YES, 6, 12, self.accent);
    if (self.sel < n) {
        NSDictionary *e = shown[self.sel]; NSString *k = e[@"kind"];
        NSString *about = [e[@"about"] length] ? e[@"about"] : [k isEqual:@"MANUAL"] ? @"Opens in your PDF reader." : [k isEqual:@"VIDEO"] ? @"Plays in your video player."
                        : [k isEqual:@"PICTURE"] ? @"Opens in your picture viewer." : [k isEqual:@"LINK"] ? @"Opens in your web browser."
                        : [k isEqual:@"FOLDER"] ? @"Opens the folder." : @"Opens with the program your Mac has for it.";
        text(about, NSMakeRect(EX_X0, H - 50, 580, 28), F_BODY, 12, rgb(0xC6D0E2, 1), NSTextAlignmentLeft, 0, NO);
    }
    NSMutableArray *hs = [@[@[@"ENTER", @"Open", @(HIT_OPEN)], @[@"O", @"Open folder", @(HIT_FOLDER)]] mutableCopy];
    if (secs.count > 1) [hs addObject:@[@"TAB", @"Section", @(HIT_NONE)]];
    [hs addObject:@[@"ESC", @"Back", @(HIT_BACK)]];
    [self hints:hs];
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
@property NSUserDefaults *defaults; @property NSString *domainName;   /* its settings domain, and that domain's name */
@property BOOL ready;
@property NSImage *logo;                       /* logo_hd (tools/fetch_art.py), else the disc's logo */
@property NSArray<NSDictionary *> *heroes;      /* its key art, as the hero layout shows it (launcher_games.c) */
@property uint32_t accentRGB, washRGB;          /* its colour, and the wash behind what is focused */
@property NSArray<TSPanel *> *panels;
@property TSRow *display, *resolution, *widescreen, *filtering, *framerate, *soften, *interp, *fps, *renderer,
                *scheme, *mouse, *crosshair, *link, *router, *saves;
/* Play Together: directly or through an online server (recompose tools/online_server), its address and the session
 * code everyone types; the rows the panel shows for what is chosen. */
@property TSRow *via, *peerRow, *serverRow, *codeRow, *portRow, *joinCodeRow; @property TSPanel *netPanel;
@property NSString *serverAddr, *code, *sysPort, *coopPort;   /* code: the session code through a server, the join code directly */
@end
@implementation TSGame
- (BOOL)kbm { return [self.scheme.value isEqual:@"1"]; }
@end

/* A row whose values are the settings file's own words: what the file says, else what this game's launcher
 * remembered before it used the file (`legacy`), else `dflt`. Until this launcher has saved the file once
 * (g_legacy_first), what the earlier launcher remembered comes first: it handed its settings over as environment
 * variables, which won over the file, so they are what the game was played with, whatever an older file says. A value
 * the file has that the row does not list (a frame cap typed by hand, say) is added, so opening the launcher never
 * changes it. */
static BOOL g_legacy_first;
static TSRow *conf_row(NSString *title, NSArray<NSDictionary *> *choices, NSString *have, NSString *legacy, NSString *dflt)
{
    NSString *v = g_legacy_first ? (legacy ?: have ?: dflt) : (have ?: legacy ?: dflt);
    if (index_of(choices, v, -1) < 0) choices = [choices arrayByAddingObject:@{@"value": v, @"label": v, @"note": @"As the settings file has it"}];
    return row(title, choices, v, index_of(choices, dflt, 0));
}

@interface Launcher : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window; @property (strong) TSLaunchView *view;
@property (strong) NSArray<TSGame *> *games; @property NSInteger current;
@property NSString *lastPickPath;                   /* <user dir>/launcher_game.txt: the game last picked, "ts2" or "fp" (the PC's launcher keeps it there too) */
@property (strong) TSRow *updates;
@property (strong) TSHeroView *hero; @property NSString *userDir;
@property NSInteger probeState; @property double copiedAt;   /* the router asked: 0 not yet, 1 asking, 2 answered; when the address was copied */
@end

@implementation Launcher { NetUpnpResult _probe; }
- (TSGame *)game { return self.games[self.current]; }
/* The settings domain a game's launcher used as its own app; a test (TS2_LAUNCHER_PREFS=<prefix>) gets its own. */
static NSString *domain_name(NSString *bundleID)
{
    const char *test = getenv("TS2_LAUNCHER_PREFS");
    return test && *test ? [NSString stringWithFormat:@"%s.%@", test, bundleID] : bundleID;
}
static NSUserDefaults *domain(NSString *bundleID)
{
    const char *test = getenv("TS2_LAUNCHER_PREFS");
    if (test && *test) return [[NSUserDefaults alloc] initWithSuiteName:domain_name(bundleID)];
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
    g.defaults = domain(bid); g.domainName = domain_name(bid);
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
    g.logo = image_at(artDirs, @"logo_hd.png") ?: image_at(artDirs, @"logo.png");
    /* The key art (tools/fetch_art.py, from the LaunchBox Games Database), as src/launcher_games.c frames it: a little
     * larger than the window so it can drift, its crop kept high, the menu being across the bottom. Never a
     * screenshot: without the key art the ink alone. */
    NSArray *spec = [key isEqual:@"fp"] ? @[@[@"key_portal", @0.20, @-40], @[@"key_corridor", @0.25, @40]]
                                        : @[@[@"key_cover", @0.30, @-40], @[@"key_pair", @0.25, @40], @[@"key_alley", @0.30, @-40]];
    NSMutableArray *heroes = [NSMutableArray array];
    for (NSArray *h in spec) {
        NSImage *img = image_at(artDirs, [h[0] stringByAppendingString:@".jpg"]) ?: image_at(artDirs, [h[0] stringByAppendingString:@".png"]);
        if (img) [heroes addObject:@{@"image": img, @"zoom": @1.06, @"fx": @0.5, @"fy": h[1], @"dx": h[2], @"dy": @0}];
    }
    g.heroes = heroes;
    g.accentRGB = [key isEqual:@"fp"] ? 0x7CB6FF : 0x9C8CFF;            /* its front end's blue; TimeSplitters 2's violet */
    g.washRGB = [key isEqual:@"fp"] ? 0x2A6EE0 : 0x6A4CF0;
    [self buildRows:g];
    return g;
}
- (void)buildRows:(TSGame *)g
{
    NSDictionary<NSString *, NSString *> *c = conf_read(g.confPath);
    /* what the earlier launcher saved: only what is stored, not the defaults registered above */
    NSDictionary *stored = [NSUserDefaults.standardUserDefaults persistentDomainForName:g.domainName] ?: @{};
    g_legacy_first = ![stored[@"confSaved"] boolValue];
    NSString *(^b)(NSString *) = ^NSString *(NSString *k) { return c[k] ? (off_word(c[k]) ? @"0" : @"1") : nil; };   /* a yes/no line */
    NSString *(^old)(NSString *) = ^NSString *(NSString *k) { return stored[k] ? [NSString stringWithFormat:@"%@", stored[k]] : nil; };
    NSString *(^oldb)(NSString *) = ^NSString *(NSString *k) { return stored[k] ? ([stored[k] boolValue] ? @"1" : @"0") : nil; };

    /* Graphics Options */
    g.display = conf_row(@"Display", @[@{@"value": @"0", @"label": @"Window", @"note": @"A window on the desktop; Alt-Return switches in the game"},
                                       @{@"value": @"1", @"label": @"Full Screen", @"note": @"The whole display, Dock and menu bar out of the way"}], b(@"fullscreen"), oldb(@"fullscreen"), @"0");
    NSMutableArray *res = [NSMutableArray array];
    for (int s = 1; s <= 4; s++)
        [res addObject:@{@"value": [NSString stringWithFormat:@"%d", s], @"label": [NSString stringWithFormat:@"%dx  ·  %d × %d", s, 640 * s, 480 * s], @"short": [NSString stringWithFormat:@"%dx", s],
                         @"note": s == 1 ? @"The console's own 640 × 480: softest, lightest on the GPU" : s == 2 ? @"Sharp on a Retina display at little cost (recommended)"
                                : s == 3 ? @"Sharper still; for a larger window or full screen" : @"Supersampled: the cleanest edges, the most GPU work"}];
    g.resolution = conf_row(@"Resolution", res, c[@"resolution_scale"], old(@"scale"), @"2");
    /* what 16:9 is: Future Perfect's own widescreen mode; TimeSplitters 2's camera widened (src/launcher_games.c `widescreen`) */
    NSString *wideNote = [g.key isEqual:@"fp"] ? @"16:9 in the game's own widescreen mode"
                                               : @"A wider camera, not a stretched one; menus and HUD laid out for it";
    g.widescreen = conf_row(@"Widescreen", @[@{@"value": @"1", @"label": @"16:9", @"note": wideNote},
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
    TSPanel *gp = [TSPanel new]; gp.title = @"GRAPHICS";
    gp.rows = @[g.display, g.resolution, g.widescreen, g.filtering, g.soften, g.framerate, g.interp, g.fps];
    gp.linkTitle = @"ADVANCED"; gp.linkPanel = 3;
    /* Advanced: the renderer. Metal is the Mac's; Vulkan through MoltenVK is kept here for a Mac Metal does not suit.
     * `moltenvk`, not `vulkan`: an old file's `vulkan` stays Metal (recompose's rhi.c). */
    NSString *rv = c[@"renderer"] && [c[@"renderer"].lowercaseString isEqual:@"moltenvk"] ? @"moltenvk" : (c[@"renderer"] ? @"metal" : nil);
    g.renderer = conf_row(@"Renderer", @[@{@"value": @"metal", @"label": @"Metal (default)", @"short": @"Metal", @"note": @"Apple's own graphics API, drawn by the port's own renderer: nothing in between"},
                                         @{@"value": @"moltenvk", @"label": @"Vulkan (MoltenVK)", @"short": @"MoltenVK", @"note": @"The Vulkan renderer through MoltenVK; Metal again if it cannot start"}],
                          rv, nil, @"metal");
    TSPanel *ap = [TSPanel new]; ap.title = @"ADVANCED"; ap.rows = @[g.renderer];
    ap.linkTitle = @"GRAPHICS"; ap.linkPanel = 0; ap.linkLeft = YES;
    ap.footnote = @"The renderer changes from the next start. The in-game menu (Esc) has it too, under Display › Advanced.";

    /* Controls */
    /* Keyboard & Mouse is mouse look (`mouse_look`, the game's default): the mouse turns the view. The keys are the
     * game's own either way (its title_defaults.c, or a bindings file, titles/<ID>.input.json), and a controller
     * works beside them. */
    NSString *oldScheme = stored[@"scheme"] ? ([stored[@"scheme"] isEqual:@"pad"] ? @"0" : @"1") : nil;
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
                                                                            : fp ? @"Left Shoulder  ·  Right Shoulder  ·  Stick Clicks" : @"Stick Clicks"; }, nil);
    TSRow *menus = info(@"Start · Back · Menus", ^{ return wg.kbm ? (fp ? @"Return or P  ·  Tab  ·  Arrows" : @"Return or Tab  ·  Backspace  ·  Arrows")
                                                                  : @"Start  ·  Back  ·  D-Pad"; }, nil);
    TSPanel *cp = [TSPanel new]; cp.title = @"CONTROLS"; cp.rows = @[g.scheme, g.mouse, g.crosshair, move, fire, abxy, wb, menus];
    cp.footnote = @"In the game: 1-9 weapons · the wheel swaps or zooms · Esc the PC menu · F9 frame rate · F11 screenshot · Alt-Return full screen";
    /* Play Together, as the Windows launcher's (recompose launcher.c build_link_rows, draw_link): System Link and
     * online co-op, directly or through an online server (recompose tools/online_server). Kept in the settings file
     * under the same names as everywhere (syslink, coop, online_via, online_server, syslink_host, syslink_port,
     * coop_port, syslink_code, syslink_upnp), and handed to the game for each start. */
    NSString *(^cs)(NSString *) = ^NSString *(NSString *k) { return c[k].length ? c[k] : nil; };
    NSString *oldLink = stored[@"link"], *mode = nil;
    if ([cs(@"coop") isEqual:@"host"] || [cs(@"coop") isEqual:@"join"]) mode = [@"coop-" stringByAppendingString:c[@"coop"]];
    else if ([cs(@"syslink") isEqual:@"host"] || [cs(@"syslink") isEqual:@"join"]) mode = c[@"syslink"];
    NSString *linkNote = @"Play with other copies over a network. Host: this Mac is the session your friends join. Join: play in a friend's session.";
    g.link = row(@"System Link", @[@{@"value": @"off", @"label": @"Off", @"note": linkNote}, @{@"value": @"host", @"label": @"Host a session", @"note": linkNote},
                                   @{@"value": @"join", @"label": @"Join a session", @"note": linkNote}, @{@"value": @"coop-host", @"label": @"Host online co-op", @"note": linkNote},
                                   @{@"value": @"coop-join", @"label": @"Join online co-op", @"note": linkNote}],
                 g_legacy_first ? (oldLink ?: mode ?: @"off") : (mode ?: oldLink ?: @"off"), 0);
    g.via = row(@"Connect", @[@{@"value": @"direct", @"label": @"Directly", @"note": @"Directly: the host's router lets friends in (UPnP, or a port forwarded by hand). Through an online server: everyone connects to one server, nobody opens a port. SET UP A SERVER, above the rows, shows how to run one."},
                              @{@"value": @"server", @"label": @"Through an online server", @"note": @"Directly: the host's router lets friends in (UPnP, or a port forwarded by hand). Through an online server: everyone connects to one server, nobody opens a port. SET UP A SERVER, above the rows, shows how to run one."}],
                cs(@"online_via") ?: stored[@"via"] ?: @"direct", 0);
    g.serverAddr = cs(@"online_server") ?: stored[@"server"] ?: @"";
    g.code = cs(@"syslink_code") ?: stored[@"code"] ?: @"";
    g.peerAddr = cs(@"syslink_host") ?: stored[@"peer"] ?: @"";
    g.sysPort = [cs(@"syslink_port") isEqual:@"27610"] ? @"" : cs(@"syslink_port") ?: @"";
    g.coopPort = [cs(@"coop_port") isEqual:@"27620"] ? @"" : cs(@"coop_port") ?: @"";
    __weak Launcher *wl = self;
    /* a text row: typed in a small sheet; its dim words while empty */
    TSRow *(^textRow)(NSString *, NSString *, NSString *, NSString *, NSString *(^)(void), void (^)(void)) =
        ^TSRow *(NSString *title, NSString *note, NSString *empty, NSString *key, NSString *(^value)(void), void (^ask)(void)) {
            TSRow *r = [TSRow new]; r.title = title; r.placeholder = empty;
            r.choices = @[@{@"value": @"", @"label": @"", @"note": note}]; r.summary = value; r.activate = ask; return r; };
    g.serverRow = textRow(@"Server address", @"The online server everyone uses, like name.fly.dev, with :port if not 27630. Type it, or ⌘V to paste.",
                          @"type the server's address", @"serverAddr", ^NSString * { return wg.serverAddr; },
                          ^{ [wl askText:@"Server address" info:@"The online server everyone uses, like name.fly.dev, with :port if not 27630." placeholder:@"name.fly.dev" key:@"serverAddr"]; });
    g.codeRow = textRow(@"Session code", @"Everyone in the game types the same code: it is how the server puts you together, and keeps others out. At least four characters.",
                        @"type a code", @"code", ^NSString * { return wg.code; },
                        ^{ [wl askText:@"Session code" info:@"Everyone in the game types the same code: it is how the server puts you together, and keeps others out. At least four characters." placeholder:@"a code" key:@"code"]; });
    g.peerRow = textRow(@"Host's address", @"What the host gave you, like 81.2.3.4 or a name, with :port if theirs is not the port below. Type it, or ⌘V to paste.",
                        @"type the host's address", @"peerAddr", ^NSString * { return wg.peerAddr; },
                        ^{ [wl askText:@"Host's address" info:@"What the host gave you, like 81.2.3.4 or a name, with :port if theirs is not the port below." placeholder:@"192.168.1.20" key:@"peerAddr"]; });
    g.portRow = textRow(@"Port", @"", @"27610", @"port", ^NSString * { return [wg.link.value hasPrefix:@"coop"] ? wg.coopPort : wg.sysPort; },
                        ^{ [wl askPort]; });
    g.joinCodeRow = textRow(@"Join code", @"Optional. Only consoles with the same code get in; empty lets in anyone who has the address. Not case-sensitive.",
                            @"none", @"code", ^NSString * { return wg.code; },
                            ^{ [wl askText:@"Join code" info:@"Optional. Only consoles with the same code get in; empty lets in anyone who has the address. Not case-sensitive." placeholder:@"none" key:@"code"]; });
    NSString *upnp = c[@"syslink_upnp"] ? (off_word(c[@"syslink_upnp"]) ? @"0" : @"1") : stored[@"upnp"] ? ([stored[@"upnp"] boolValue] ? @"1" : @"0") : nil;
    NSString *upnpNote = @"Ask the router to forward the port to this Mac (UPnP) while you host, so friends on the internet can join. Friends on your own network can join either way.";
    g.router = row(@"Open the router", @[@{@"value": @"0", @"label": @"Off", @"note": upnpNote}, @{@"value": @"1", @"label": @"On", @"note": upnpNote}],
                   g_legacy_first ? (stored[@"upnp"] ? upnp : @"1") : (upnp ?: @"1"), 1);
    TSPanel *np = [TSPanel new]; np.title = @"PLAY TOGETHER"; g.netPanel = np;
    np.linkTitle = @"SET UP A SERVER"; np.linkPanel = -2;               /* the online server's page */
    [self netRows:g];
    g.panels = @[gp, cp, np, ap];

    /* the game's own save folder: UDATA/<its title id> */
    NSString *saves = [g.dataPath stringByAppendingPathComponent:[@"game/UDATA" stringByAppendingPathComponent:g.titleID.lowercaseString]];
    g.saves = [TSRow new]; g.saves.title = @"Saves";
    g.saves.choices = @[@{@"value": @"", @"label": @"Open", @"note": [@"Your profiles and story progress: " stringByAppendingString:[saves stringByAbbreviatingWithTildeInPath]]}];
    g.saves.activate = ^{ [[NSFileManager defaultManager] createDirectoryAtPath:saves withIntermediateDirectories:YES attributes:nil error:nil];
                          [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:saves isDirectory:YES]]; };
}
/* The Play Together rows for what is chosen, as build_link_rows: through a server its address and the session code;
 * directly the host's address (joining), the port, the join code (System Link) and the router (hosting). */
- (void)netRows:(TSGame *)g
{
    NSString *m = g.link.value; BOOL off = [m isEqual:@"off"], server = !off && [g.via.value isEqual:@"server"];
    BOOL coop = [m hasPrefix:@"coop"], hosts = [m hasSuffix:@"host"], joins = [m hasSuffix:@"join"];
    NSMutableArray *rows = [NSMutableArray arrayWithObject:g.link];
    if (!off) [rows addObject:g.via];
    if (server) [rows addObjectsFromArray:@[g.serverRow, g.codeRow]];
    else if (!off) {
        if (joins) [rows addObject:g.peerRow];
        g.portRow.placeholder = coop ? @"27620" : @"27610";
        g.portRow.choices = @[@{@"value": @"", @"label": @"", @"note": hosts ? @"The UDP port friends join on. Change it only if something else on this Mac or your router already uses it."
                                                                             : @"The host's port, when their address does not end in one."}];
        [rows addObject:g.portRow];
        if (!coop) [rows addObject:g.joinCodeRow];
        if (hosts) [rows addObject:g.router];
    }
    g.netPanel.rows = rows;
    if (self.view.open == 2 && self.view.rowFocus >= (NSInteger)rows.count) self.view.rowFocus = (NSInteger)rows.count - 1;
    if (hosts && !server && [g.router.value isEqual:@"1"]) [self probeRouter];
}
- (void)askText:(NSString *)title info:(NSString *)info placeholder:(NSString *)ph key:(NSString *)key
{
    TSGame *g = self.game;
    NSAlert *a = [NSAlert new]; a.messageText = title; a.informativeText = info;
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)]; f.stringValue = [g valueForKey:key] ?: @""; f.placeholderString = ph;
    a.accessoryView = f; [a addButtonWithTitle:@"OK"]; [a addButtonWithTitle:@"Cancel"];
    [a.window setInitialFirstResponder:f];
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    [g setValue:[f.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] forKey:key];
    [self save]; self.view.needsDisplay = YES;
}
- (void)askPort
{
    TSGame *g = self.game; BOOL coop = [g.link.value hasPrefix:@"coop"];
    NSAlert *a = [NSAlert new]; a.messageText = @"Port"; a.informativeText = g.portRow.choices[0][@"note"];
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 120, 24)]; f.stringValue = coop ? g.coopPort : g.sysPort; f.placeholderString = coop ? @"27620" : @"27610";
    a.accessoryView = f; [a addButtonWithTitle:@"OK"]; [a addButtonWithTitle:@"Cancel"];
    [a.window setInitialFirstResponder:f];
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    int p = f.stringValue.intValue; NSString *v = p >= 1 && p <= 65535 ? [NSString stringWithFormat:@"%d", p] : @"";   /* anything else: the default */
    if (coop) g.coopPort = v; else g.sysPort = v;
    [self save]; self.view.needsDisplay = YES;
}
/* The port in use: what was typed, else the mode's default. */
- (int)portOf:(TSGame *)g { NSString *p = [g.link.value hasPrefix:@"coop"] ? g.coopPort : g.sysPort; return p.intValue > 0 ? p.intValue : [g.link.value hasPrefix:@"coop"] ? 27620 : 27610; }
/* The router's internet address (recompose net_upnp.c, as the Windows launcher asks it), once, off the main thread. */
- (void)probeRouter
{
    if (self.probeState) return;
    self.probeState = 1;
    if (getenv("TS2_LAUNCHER_SHOT")) { memset(&_probe, 0, sizeof _probe); net_upnp_probe(&_probe); self.probeState = 2; return; }   /* a picture waits for the answer */
    __weak Launcher *ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NetUpnpResult r; memset(&r, 0, sizeof r); net_upnp_probe(&r);
        dispatch_async(dispatch_get_main_queue(), ^{ Launcher *s = ws; if (!s) return; s->_probe = r; s.probeState = 2; s.view.needsDisplay = YES; });
    });
}
- (NSString *)lanAddress { char a[64]; return net_local_address(a, sizeof a) ? @(a) : lan_address(); }
/* What a player gives their friends (link_share_address): through a server, the server and the session code; a
 * host, the router's internet address when it gave one, else this Mac's on its network. */
- (NSString *)shareText
{
    TSGame *g = self.game;
    if (![g.link.value isEqual:@"off"] && [g.via.value isEqual:@"server"])
        return [NSString stringWithFormat:@"Server %@   Session code %@", g.serverAddr, g.code.length ? g.code : @"(none yet)"];
    if ([g.router.value isEqual:@"1"] && self.probeState == 2 && _probe.state == NET_UPNP_FOUND) return [NSString stringWithFormat:@"%s:%d", _probe.external, [self portOf:g]];
    return [NSString stringWithFormat:@"%@:%d", self.lanAddress, [self portOf:g]];
}
- (BOOL)canShare
{
    TSGame *g = self.game; NSString *m = g.link.value;
    if (![m isEqual:@"off"] && [g.via.value isEqual:@"server"]) return g.serverAddr.length > 0;
    return [m hasSuffix:@"host"];
}
- (void)copyShare
{
    if (!self.canShare) return;
    [NSPasteboard.generalPasteboard clearContents]; [NSPasteboard.generalPasteboard setString:self.shareText forType:NSPasteboardTypeString];
    self.copiedAt = CACurrentMediaTime(); self.view.needsDisplay = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ self.view.needsDisplay = YES; });
}
/* The box under the rows (draw_link): its heading, its lines (each [text, bright]), and what it says. */
- (NSDictionary *)linkInfo
{
    TSGame *g = self.game; NSString *m = g.link.value; BOOL coop = [m hasPrefix:@"coop"], hosts = [m hasSuffix:@"host"];
    BOOL copied = CACurrentMediaTime() - self.copiedAt < 1.5;
    if (![m isEqual:@"off"] && [g.via.value isEqual:@"server"]) {
        BOOL ok = g.code.length >= 4;
        return @{@"heading": @"THROUGH AN ONLINE SERVER",
                 @"lines": @[@[[@"Server         " stringByAppendingString:g.serverAddr.length ? g.serverAddr : @"not set: type its address above"], @(g.serverAddr.length > 0)],
                             @[[@"Session code   " stringByAppendingString:ok ? g.code : @"at least four characters, the same for everyone"], @(ok)]],
                 @"body": [NSString stringWithFormat:@"%@  Give your friends both; nobody opens a port. %@ No server yet? SET UP A SERVER, above the rows, shows how to run one on Fly.io.",
                           copied ? @"Copied." : @"⌘C or a click here copies them.",
                           coop ? ([m hasSuffix:@"host"] ? @"Start your game first: you are controller 1, your friend controller 2."
                                                         : @"The host starts their game first; you are controller 2 in their game.")
                                : @"Then host or join a game in the game's own System Link menu."],
                 @"share": @YES};
    }
    if (hosts) {
        int port = [self portOf:g]; NSString *net; BOOL bright = NO;
        if (![g.router.value isEqual:@"1"]) net = [NSString stringWithFormat:@"On the internet      only with UDP port %d forwarded to this Mac by hand, or over a virtual network", port];
        else if (self.probeState != 2) net = @"On the internet      asking the router...";
        else if (_probe.state == NET_UPNP_FOUND) { net = [NSString stringWithFormat:@"On the internet      %s:%d   (the router is asked to open it when the game starts)", _probe.external, port]; bright = YES; }
        else net = [@"On the internet      " stringByAppendingString:@(_probe.detail).length ? @(_probe.detail) : @"the router did not answer (UPnP is off, or there is none)"];
        NSString *fw = @"macOS may ask to let the game accept incoming connections the first time: allow it.";
        return @{@"heading": @"TELL YOUR FRIENDS",
                 @"lines": @[@[[NSString stringWithFormat:@"On your network      %@:%d", self.lanAddress, port], @YES], @[net, @(bright)]],
                 @"body": [NSString stringWithFormat:@"%@  %@ %@", copied ? @"Copied." : @"⌘C or a click here copies it.", fw,
                           coop ? @"You are controller 1 and your friend controller 2 in one game, each seeing their own view: pick its two-player mode together, as on one console."
                                : @"Then host or join a game in the game's own System Link menu."],
                 @"share": @YES};
    }
    if ([m isEqual:@"coop-join"])
        return @{@"heading": @"JOINING CO-OP", @"lines": @[], @"body": @"Ask the host for their address. Nothing needs opening on your router. Your game starts from the host's saves and you are controller 2 in their game, with your own controller 1. Both copies must be the same build with the same Widescreen setting; the log beside the game says why if the host turns you away."};
    if ([m isEqual:@"join"])
        return @{@"heading": @"JOINING", @"lines": @[], @"body": @"Ask the host for their address, and the join code if they set one. Nothing needs opening on your router. Start the game and open its System Link menu: games anyone in the session hosts appear there. If none does, the log beside the game says whether the host answered."};
    return @{@"heading": @"PLAY OVER A NETWORK", @"lines": @[], @"body": @"Consoles linked together play in one game, as they did with a cable or a network switch. One player hosts the session, up to 15 more join it, from the same network or over the internet. Each needs their own copy of the game."};
}
/* The game the window shows: its key art (sliding in from the side it is on, `dir`), its logo and colours, its
 * panels; the other game's logo over the row's end. */
- (void)showGame:(NSInteger)i slide:(NSInteger)dir
{
    self.current = i; TSGame *g = self.game; TSLaunchView *v = self.view;
    [self.hero showHeroes:g.heroes slide:dir];
    v.logo = g.logo; v.gameName = g.name; v.cardName = g.cardName; v.accentRGB = g.accentRGB; v.washRGB = g.washRGB;
    v.panels = g.panels; v.fallback = [g.heroes valueForKey:@"image"];
    NSInteger other = [self otherGame:1];
    v.otherName = other >= 0 ? self.games[other].cardName : nil; v.otherLogo = other >= 0 ? self.games[other].logo : nil;
    NSMutableArray *items = [@[@(IT_PLAY), @(IT_GRAPHICS), @(IT_CONTROLS), @(IT_ONLINE), @(IT_SAVES), @(IT_EXTRAS)] mutableCopy];
    if (![self.updates.choices[0][@"label"] isEqual:@"Unavailable"]) [items addObject:@(IT_UPDATES)];   /* with an updater */
    [items addObject:@(IT_QUIT)];
    v.items = items;
    if (v.extrasOpen) [self scanExtras];
    v.switchedAt = dir ? CACurrentMediaTime() : 0;
    [v animate];
}
/* The next game along the list, `dir` +1 or -1, that is installed; -1 for none. */
- (NSInteger)otherGame:(NSInteger)dir
{
    NSInteger n = (NSInteger)self.games.count;
    for (NSInteger k = 1; k < n; k++) { NSInteger i = ((self.current + dir * k) % n + n) % n; if (self.games[i].ready) return i; }
    return -1;
}
- (void)switchGame:(NSInteger)dir
{
    NSInteger i = [self otherGame:dir];
    if (i < 0 || i == self.current) return;
    [self showGame:i slide:dir];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.lastPickPath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [[self.game.key stringByAppendingString:@"\n"] writeToFile:self.lastPickPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
/* What a menu item is set to, or what it does: under the row while it is focused. */
- (NSString *)captionFor:(NSInteger)kind
{
    TSGame *g = self.game;
    switch (kind) {
    case IT_PLAY: return g.ready ? g.line : [@"Not installed: " stringByAppendingString:g.missing];
    case IT_GRAPHICS: {
        NSString *res = [g.resolution.value isEqual:@"1"] ? @"CONSOLE RESOLUTION" : [g.resolution.value stringByAppendingString:@"×"];
        return [NSString stringWithFormat:@"%@%@%@%@%@", [g.display.value isEqual:@"1"] ? @"FULLSCREEN" : @"WINDOW", DOT, res, DOT, [g.widescreen.value isEqual:@"1"] ? @"16:9" : @"4:3"];
    }
    case IT_CONTROLS: return g.kbm ? @"KEYS & MOUSE" : @"CONTROLLER";
    case IT_ONLINE: {
        NSString *m = g.link.value;
        if (![m isEqual:@"off"] && [g.via.value isEqual:@"server"])
            return [NSString stringWithFormat:@"%@%@THROUGH %@", [m hasPrefix:@"coop"] ? @"CO-OP" : @"SYSTEM LINK", DOT, g.serverAddr.length ? g.serverAddr.uppercaseString : @"AN ONLINE SERVER"];
        return [m isEqual:@"coop-host"] ? @"CO-OP" DOT @"HOSTING" : [m isEqual:@"coop-join"] ? @"CO-OP" DOT @"JOINING"
             : [m isEqual:@"host"] ? @"SYSTEM LINK" DOT @"HOST" : [m isEqual:@"join"] ? @"SYSTEM LINK" DOT @"JOIN" : @"ONLINE CO-OP" DOT @"SYSTEM LINK";
    }
    case IT_SAVES: return @"OPENS THE GAME'S SAVES FOLDER";
    case IT_EXTRAS: {
        NSUInteger n = [self extrasOf:g].count;
        return n ? [NSString stringWithFormat:@"%lu %@%@MANUALS, VIDEOS, PICTURES", (unsigned long)n, n == 1 ? @"ITEM" : @"ITEMS", DOT] : @"MANUALS, VIDEOS, PICTURES";
    }
    case IT_UPDATES: return self.updates.choices[0][@"label"];
    }
    return nil;
}
- (void)item:(NSInteger)kind
{
    TSLaunchView *v = self.view;
    switch (kind) {
    case IT_PLAY: [self play]; break;
    case IT_GRAPHICS: [v openPanel:0]; break;
    case IT_CONTROLS: [v openPanel:1]; break;
    case IT_ONLINE: [v openPanel:2]; break;
    case IT_SAVES: self.game.saves.activate(); break;
    case IT_EXTRAS: [self scanExtras]; v.section = v.sel = v.top = 0; v.extrasOpen = YES; v.needsDisplay = YES; break;
    case IT_UPDATES: if (self.updates.activate) self.updates.activate(); v.needsDisplay = YES; break;
    case IT_QUIT: [NSApp terminate:nil]; break;
    }
}

// ------------------------------------------------ the extras
/* A game's extras folders: the one the launcher opens and makes (<user dir>/extras/<ID>, as the Windows launcher's
 * %APPDATA%\xboxrecomp\extras\<ID>), and an extras folder in the game's own data folder. */
- (NSString *)extrasDirOf:(TSGame *)g { return [[self.userDir stringByAppendingPathComponent:@"extras"] stringByAppendingPathComponent:g.titleID.uppercaseString]; }
static NSString *extra_kind(NSString *name, BOOL dir)
{
    if (dir) return @"FOLDER";
    NSString *e = name.pathExtension.lowercaseString;
    if ([@[@"pdf", @"epub", @"xps", @"djvu", @"cbz", @"cbr"] containsObject:e]) return @"MANUAL";
    if ([@[@"mp4", @"m4v", @"mkv", @"webm", @"mov", @"avi", @"wmv", @"mpg", @"mpeg"] containsObject:e]) return @"VIDEO";
    if ([@[@"jpg", @"jpeg", @"png", @"gif", @"webp", @"bmp"] containsObject:e]) return @"PICTURE";
    if ([@[@"url", @"webloc"] containsObject:e]) return @"LINK";
    return @"FILE";
}
static NSString *extra_section(NSString *kind)
{
    return [kind isEqual:@"MANUAL"] ? @"Manuals" : [kind isEqual:@"VIDEO"] ? @"Videos" : [kind isEqual:@"PICTURE"] || [kind isEqual:@"FOLDER"] ? @"Gallery"
         : [kind isEqual:@"LINK"] ? @"Links" : @"Other";
}
static NSString *extra_title(NSString *name)
{
    return [[name.stringByDeletingPathExtension stringByReplacingOccurrencesOfString:@"_" withString:@" "] stringByReplacingOccurrencesOfString:@"-" withString:@" "];
}
/* A link file's address: a .url's URL= line, a .webloc's URL. */
static NSString *link_of(NSString *path)
{
    if ([path.pathExtension.lowercaseString isEqual:@"webloc"]) return [NSDictionary dictionaryWithContentsOfFile:path][@"URL"];
    for (NSString *l in [[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet])
        if ([l hasPrefix:@"URL="]) return [l substringFromIndex:4];
    return nil;
}
/* What a folder of extras has, as the Windows launcher reads it (recompose launcher_extras.c): first what its
 * extras.json lists, in its order and with its titles, sections and pictures; then every other file, by name. A
 * picture named as another file is that file's picture. */
static void extras_in(NSString *dir, NSMutableArray<NSMutableDictionary *> *out)
{
    NSFileManager *fm = NSFileManager.defaultManager; BOOL isDir = NO;
    if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) return;
    NSMutableSet *listed = [NSMutableSet set];
    NSData *json = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"extras.json"]];
    id doc = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
    NSArray *items = [doc isKindOfClass:NSDictionary.class] ? doc[@"items"] : [doc isKindOfClass:NSArray.class] ? doc : nil;
    for (NSDictionary *o in [items isKindOfClass:NSArray.class] ? items : @[]) {
        if (![o isKindOfClass:NSDictionary.class]) continue;
        NSMutableDictionary *e = [NSMutableDictionary dictionary]; NSString *file = o[@"file"], *url = o[@"url"];
        if ([url isKindOfClass:NSString.class] && url.length) { e[@"target"] = url; e[@"kind"] = @"LINK"; }
        else if ([file isKindOfClass:NSString.class] && file.length) {
            NSString *path = [dir stringByAppendingPathComponent:file]; BOOL d = NO;
            if (![fm fileExistsAtPath:path isDirectory:&d]) continue;            /* named, but not there */
            e[@"target"] = path; e[@"kind"] = extra_kind(file, d); [listed addObject:path.lowercaseString];
        } else continue;
        e[@"title"] = [o[@"title"] isKindOfClass:NSString.class] ? o[@"title"] : extra_title(file ?: url);
        e[@"about"] = [o[@"about"] isKindOfClass:NSString.class] ? o[@"about"] : @"";
        e[@"section"] = [o[@"section"] isKindOfClass:NSString.class] ? o[@"section"] : extra_section(e[@"kind"]);
        if ([o[@"picture"] isKindOfClass:NSString.class]) { e[@"picturePath"] = [dir stringByAppendingPathComponent:o[@"picture"]]; [listed addObject:[e[@"picturePath"] lowercaseString]]; }
        else if ([e[@"kind"] isEqual:@"PICTURE"]) e[@"picturePath"] = e[@"target"];
        [out addObject:e];
    }
    NSArray *names = [[fm contentsOfDirectoryAtPath:dir error:nil] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."] || [name.lowercaseString isEqual:@"extras.json"]) continue;
        NSString *path = [dir stringByAppendingPathComponent:name]; BOOL d = NO;
        if ([listed containsObject:path.lowercaseString]) continue;
        [fm fileExistsAtPath:path isDirectory:&d];
        NSString *kind = extra_kind(name, d), *stem = name.stringByDeletingPathExtension, *pic = nil; BOOL paired = NO;
        for (NSString *other in names)
            if (![other isEqual:name] && [other.stringByDeletingPathExtension isEqual:stem]) {
                BOOL otherPic = [extra_kind(other, NO) isEqual:@"PICTURE"];
                if ([kind isEqual:@"PICTURE"] && !otherPic) paired = YES;        /* this picture is that file's */
                if (![kind isEqual:@"PICTURE"] && otherPic && !pic) pic = [dir stringByAppendingPathComponent:other];
            }
        if (paired) continue;
        NSMutableDictionary *e = [@{@"target": path, @"kind": kind, @"title": d ? name : extra_title(name), @"about": @"", @"section": extra_section(kind)} mutableCopy];
        if ([kind isEqual:@"LINK"]) { NSString *u = link_of(path); if (u.length) e[@"target"] = u; }
        if ([kind isEqual:@"PICTURE"]) pic = path;
        if ([kind isEqual:@"FOLDER"])
            for (NSString *inner in [[fm contentsOfDirectoryAtPath:path error:nil] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)])
                if ([extra_kind(inner, NO) isEqual:@"PICTURE"]) { pic = [path stringByAppendingPathComponent:inner]; break; }
        if (pic) e[@"picturePath"] = pic;
        [out addObject:e];
    }
}
- (NSArray<NSMutableDictionary *> *)extrasOf:(TSGame *)g
{
    NSMutableArray *out = [NSMutableArray array];
    extras_in([self extrasDirOf:g], out);
    extras_in([g.dataPath stringByAppendingPathComponent:@"extras"], out);
    return out;
}
- (void)scanExtras
{
    NSArray<NSMutableDictionary *> *ex = [self extrasOf:self.game];
    for (NSMutableDictionary *e in ex) {                                    /* each one's own picture, if it has one */
        NSImage *img = e[@"picturePath"] ? [[NSImage alloc] initWithContentsOfFile:e[@"picturePath"]] : nil;
        if (img.size.width > 2) e[@"picture"] = img;
    }
    self.view.extras = ex; self.view.extrasDir = [self extrasDirOf:self.game];
}
- (void)openExtra:(NSDictionary *)e
{
    NSString *t = e[@"target"];
    NSURL *u = [t hasPrefix:@"/"] ? [NSURL fileURLWithPath:t] : [NSURL URLWithString:t];
    if (u) [[NSWorkspace sharedWorkspace] openURL:u];
}
- (void)openExtrasFolder
{
    NSString *dir = [self extrasDirOf:self.game];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:dir isDirectory:YES]];
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

    self.userDir = userDir;
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, W, H)]; root.wantsLayer = YES;
    self.hero = [[TSHeroView alloc] initWithFrame:root.bounds]; self.hero.still = getenv("TS2_LAUNCHER_SHOT") != NULL;
    [root addSubview:self.hero];
    TSLaunchView *v = [[TSLaunchView alloc] initWithFrame:root.bounds]; self.view = v; [root addSubview:v];
    v.hover = v.pressed = HIT_NONE; v.focus = 0; v.open = -1;
    /* the online server's files (recompose tools/online_server), which mac/install.sh puts in the app */
    NSString *srv = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"online_server"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[srv stringByAppendingPathComponent:@"server.py"]]) v.serverFolder = srv;
    if (getenv("TS2_LAUNCHER_SERVER_FOLDER")) v.serverFolder = @(getenv("TS2_LAUNCHER_SERVER_FOLDER"));
    [self setupUpdates];
    /* the game picked last time, if it is still here; else the first that is (a one-game app: its own) */
    NSInteger pick = -1; NSString *last = getenv("TS2_LAUNCHER_GAME") ? @(getenv("TS2_LAUNCHER_GAME")) : [[NSString stringWithContentsOfFile:self.lastPickPath encoding:NSUTF8StringEncoding error:nil]
                                                                                       stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *own = NSBundle.mainBundle.infoDictionary[@"TS2Exe"];
    for (NSInteger i = 0; i < (NSInteger)self.games.count; i++) if ([self.games[i].key isEqual:last] && self.games[i].ready) pick = i;
    for (NSInteger i = 0; pick < 0 && i < (NSInteger)self.games.count; i++) if (own && [self.games[i].exe isEqual:own] && self.games[i].ready) pick = i;
    for (NSInteger i = 0; pick < 0 && i < (NSInteger)self.games.count; i++) if (self.games[i].ready) pick = i;
    [self showGame:MAX(pick, 0) slide:0];
    __weak Launcher *ws = self;
    v.caption = ^NSString *(NSInteger kind) { return [ws captionFor:kind]; };
    v.onItem = ^(NSInteger kind) { [ws item:kind]; };
    v.onSwitch = ^(NSInteger dir) { [ws switchGame:dir]; };
    v.onChange = ^{ [ws save]; };
    v.onOpenExtra = ^(NSDictionary *e) { [ws openExtra:e]; };
    v.onExtrasFolder = ^{ [ws openExtrasFolder]; };
    v.linkInfo = ^NSDictionary * { return [ws linkInfo]; };
    v.onCopyShare = ^{ [ws copyShare]; };

    const char *shot = getenv("TS2_LAUNCHER_SHOT");
    if (shot) {                                                          /* development: the window as an image */
        if (getenv("TS2_LAUNCHER_HOVER")) v.hover = atoi(getenv("TS2_LAUNCHER_HOVER"));
        if (getenv("TS2_LAUNCHER_FOCUS")) v.focus = atoi(getenv("TS2_LAUNCHER_FOCUS"));
        if (getenv("TS2_LAUNCHER_PANEL")) [v openPanel:atoi(getenv("TS2_LAUNCHER_PANEL"))];
        if (getenv("TS2_LAUNCHER_ROWFOCUS")) v.rowFocus = atoi(getenv("TS2_LAUNCHER_ROWFOCUS"));
        if (getenv("TS2_LAUNCHER_EXTRAS")) [self item:IT_EXTRAS];
        if (getenv("TS2_LAUNCHER_HELP")) { [v openPanel:2]; [v openPanel:-2]; }
        NSBitmapImageRep *rep = [root bitmapImageRepForCachingDisplayInRect:root.bounds]; [root cacheDisplayInRect:root.bounds toBitmapImageRep:rep];
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(shot) atomically:YES];
        exit(0);
    }
    if (getenv("TS2_LAUNCHER_PLAY")) { [self play]; return; }    /* development: Play at once, no window to take the focus */
    NSWindow *w = [[NSWindow alloc] initWithContentRect:root.frame styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskFullSizeContentView
                                                backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO; w.titlebarAppearsTransparent = YES; w.titleVisibility = NSWindowTitleHidden; w.movableByWindowBackground = YES;
    w.title = NSBundle.mainBundle.infoDictionary[@"CFBundleName"] ?: @"Timeslip"; w.backgroundColor = NSColor.blackColor; w.contentView = root;
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
                             @"mouse_look": g.scheme.value, @"mouse_sensitivity": g.mouse.value, @"crosshair": g.crosshair.value,
                             /* Play Together, under the names every launcher and the game use */
                             @"syslink": [g.link.value hasPrefix:@"coop"] ? @"off" : g.link.value,
                             @"coop": [g.link.value isEqual:@"coop-host"] ? @"host" : [g.link.value isEqual:@"coop-join"] ? @"join" : @"off",
                             @"online_via": g.via.value, @"online_server": g.serverAddr ?: @"", @"syslink_code": g.code ?: @"",
                             @"syslink_host": g.peerAddr ?: @"", @"syslink_upnp": g.router.value,
                             @"syslink_port": g.sysPort.length ? g.sysPort : @"27610", @"coop_port": g.coopPort.length ? g.coopPort : @"27620"});
    [d removeObjectForKey:@"renderer"];                                 /* from when the Mac also had Vulkan */
    [d setBool:YES forKey:@"confSaved"];                                /* the file has this launcher's settings now: it comes first */
    [d setObject:g.kbm ? @"kbm" : @"pad" forKey:@"scheme"];
    [d setObject:g.link.value forKey:@"link"];
    [d setObject:g.peerAddr ?: @"" forKey:@"peer"];
    [d setBool:[g.router.value isEqual:@"1"] forKey:@"upnp"];
    [d setObject:g.via.value forKey:@"via"];
    [d setObject:g.serverAddr ?: @"" forKey:@"server"];
    [d setObject:g.code ?: @"" forKey:@"code"];
    [d synchronize];
    [self netRows:g];
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
    BOOL coop = [mode hasPrefix:@"coop-"], hosts = [mode hasSuffix:@"host"], joins = [mode hasSuffix:@"join"];
    BOOL viaServer = ![mode isEqual:@"off"] && [g.via.value isEqual:@"server"];
    if (viaServer && (!g.serverAddr.length || g.code.length < 4)) {    /* a server needs both: never a quiet fallback to direct */
        [self.view openPanel:2];
        if (!g.serverAddr.length) g.serverRow.activate();
        if (g.serverAddr.length && g.code.length < 4) g.codeRow.activate();
        if (!g.serverAddr.length || g.code.length < 4) return;
    }
    if (!viaServer && joins && !g.peerAddr.length) {                     /* directly, a joiner needs the host's address */
        [self.view openPanel:2]; g.peerRow.activate();
        if (!g.peerAddr.length) return;
    }
    NSString *game = [g.dataPath stringByAppendingPathComponent:@"game"];
    setenv("RECOMP_GAME_DIR", game.fileSystemRepresentation, 1);
    /* the graphics come from the settings file, as the launcher just wrote it; a test's folder of them is the game's too */
    if (getenv("TS2_CONF_DIR")) setenv("RECOMP_DISPLAY_CONFIG", g.confPath.fileSystemRepresentation, 1);
    /* Play Together: the launcher decides, so what an older settings file says does not */
    setenv("RECOMP_SYSLINK", coop || [mode isEqual:@"off"] ? "off" : mode.UTF8String, 1);
    setenv("RECOMP_LOCKSTEP_NET", coop ? (hosts ? "host" : "join") : "off", 1);
    setenv("RECOMP_ONLINE_VIA", viaServer ? "server" : "direct", 1);
    unsetenv("RECOMP_SYSLINK_HOST"); unsetenv("RECOMP_LOCKSTEP_PEER"); unsetenv("RECOMP_ONLINE_SERVER");
    unsetenv("RECOMP_SYSLINK_CODE"); unsetenv("RECOMP_LOCKSTEP_CODE");
    if (g.code.length) { setenv("RECOMP_SYSLINK_CODE", g.code.UTF8String, 1); setenv("RECOMP_LOCKSTEP_CODE", g.code.UTF8String, 1); }
    NSString *port = [NSString stringWithFormat:@"%d", [self portOf:g]];
    setenv(coop ? "RECOMP_LOCKSTEP_PORT" : "RECOMP_SYSLINK_PORT", port.UTF8String, 1);
    if (viaServer) {                                                     /* everyone to the server; nothing asked of a router */
        setenv("RECOMP_ONLINE_SERVER", g.serverAddr.UTF8String, 1);
        setenv("RECOMP_SYSLINK_UPNP", "0", 1); setenv("RECOMP_LOCKSTEP_UPNP", "0", 1);
    } else {
        const char *up = hosts && [g.router.value isEqual:@"1"] ? "1" : "0";
        setenv("RECOMP_SYSLINK_UPNP", up, 1); setenv("RECOMP_LOCKSTEP_UPNP", up, 1);
        if (joins) setenv(coop ? "RECOMP_LOCKSTEP_PEER" : "RECOMP_SYSLINK_HOST", g.peerAddr.UTF8String, 1);
    }
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
