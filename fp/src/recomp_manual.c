/**
 * Manual function overrides and ICALL diagnostics
 *
 * This file provides:
 *   - recomp_lookup_manual()  : intercept specific Xbox VAs with hand-written code
 *   - recomp_icall_fail_log() : log when an indirect call target can't be resolved
 *   - ICALL trace ring buffer  : globals used by the RECOMP_ICALL macro
 *
 * The recomp pipeline generates an auto-dispatch table (recomp_lookup) that
 * resolves most function addresses. recomp_lookup_manual() is called FIRST,
 * giving you a chance to override any function with a custom implementation.
 *
 * Common reasons to add manual overrides:
 *   - Trace a function to understand call flow (wrap the generated version)
 *   - Fix a function the lifter translated incorrectly
 *   - Stub out a function that crashes (return early, set eax to a safe value)
 *   - Redirect a function to a native implementation (e.g., skip CRT init)
 *   - Intercept D3D/audio calls for custom rendering or sound
 */

#include <stdio.h>
#include <stdint.h>
#include <stddef.h>   /* ptrdiff_t: not in stdlib.h off MSVC */
#include <stdlib.h>   /* getenv, exit: the spin verdict below */
#include <string.h>   /* strcmp: RECOMP_ICALL_FATAL */
#include <math.h>     /* tan, atan: the field of view and the weapon in hand */

/* One diagnostic report, one piece.
 *
 * Each report below is a dozen fprintf calls and the CRT takes its lock per
 * call, so with more than one guest thread running the lines interleave in
 * the middle of a report. Dino Crisis 3 runs six workers once it is past its
 * menus, and its log came out like this:
 *
 *   callers: 0x004DB424 <- 0x002705B4 <- 0x002705B4[ICALL] unresolved jump
 *   target 0x41B0B870 -- 1 time(s) (total calls: 6930990)
 *
 * -- two threads' reports spliced together, with a caller list that stops
 * mid-sentence and an address that belongs to neither line as read. These
 * diagnostics exist to be read during exactly the multi-threaded bring-up
 * that breaks them.
 *
 * The CRT exposes the lock these calls were already taking one at a time, so
 * hold it across the whole report instead. */
#if defined(_MSC_VER)
#  define RECOMP_DIAG_LOCK()   _lock_file(stderr)
#  define RECOMP_DIAG_UNLOCK() _unlock_file(stderr)
#elif defined(__unix__) || defined(__APPLE__)
#  define RECOMP_DIAG_LOCK()   flockfile(stderr)
#  define RECOMP_DIAG_UNLOCK() funlockfile(stderr)
#else
#  define RECOMP_DIAG_LOCK()   ((void)0)
#  define RECOMP_DIAG_UNLOCK() ((void)0)
#endif

/* ── ICALL trace ring buffer ───────────────────────────────── */

/*
 * These globals are written by the RECOMP_ICALL macro (defined in
 * recomp_types.h) every time an indirect call is dispatched. When a
 * crash occurs, the VEH handler or recomp_icall_fail_log() can dump
 * the last 16 call targets to help you trace what happened.
 *
 * The runtime owns them: xbox_kernel defines all three in
 * src/kernel/xbox_memory_layout.c, and recomp_types.h declares them extern.
 * Declare, do not define -- a definition here as well is a duplicate symbol,
 * and a project copied from this template failed to link on all three:
 *
 *   xbox_memory_layout.obj : error LNK2005: g_icall_count already defined
 *                            in recomp_manual.obj
 */
extern volatile uint32_t g_icall_trace[16];
extern volatile uint32_t g_icall_trace_idx;
extern volatile uint64_t g_icall_count;

typedef void (*recomp_func_t)(void);

/* ── Register state (defined in xbox_memory_layout.c) ──────── */

/* The guest registers (g_eax, g_esp, g_icall_saved_esp, ...) are fields of
 * one thread-local struct, declared once in recomp_cpu.h, which the lifter
 * copies into gen/ beside the code it describes. Take them from there; never
 * redeclare one here. They used to be redeclared by hand, and a declaration
 * without the thread-local storage class linked and silently read other
 * storage, so every read got 0 -- which is why the log below once reported
 * no call site: not because the guest esp was stale, but because this file
 * was not reading the guest esp at all. The names are macros now, so a
 * redeclaration no longer compiles. */
#include "recomp/gen/recomp_cpu.h"

/* g_eax: recomp_cpu.h. */
/* The guest stack pointer. At the moment an indirect call is refused, the
 * caller has already pushed its guest return address, so the top of the
 * guest stack is the call site -- the one thing the old log did not say. */
/* g_esp: recomp_cpu.h. */
extern ptrdiff_t g_xbox_mem_offset;
/* The lifted code sections, so a value on the guest stack can be told
 * apart from data when naming the callers of a refused call. */
extern uint32_t g_xbox_code_lo;
extern uint32_t g_xbox_code_hi;
/* The esp the dispatch macro captured. Not g_esp, which is stale by the time
 * a refused call is reported. Zero when the title's generated header predates
 * this, and the log then says it has no callers rather than inventing them. */
/* g_icall_saved_esp: recomp_cpu.h. */
/* Which dispatch form was refused: 0 unknown, 1 call, 2 jump. Unknown
 * means this title was lifted before the macros published it. */
/* g_icall_dispatch_form: recomp_cpu.h. */

/* ── Manual function overrides ─────────────────────────────── */

/*
 * Return a function pointer to override the given Xbox VA, or NULL
 * to fall through to the auto-generated dispatch table.
 *
 * This is called on every indirect call (RECOMP_ICALL) and every
 * direct call through the dispatch table, so keep it fast. A chain
 * of if-statements on uint32_t compiles to a simple comparison
 * sequence; for large override tables, consider a sorted array
 * with binary search.
 *
 * Examples of common override patterns:
 *
 *   // Trace wrapper: log entry/exit around the generated function
 *   extern void sub_00012345(void);
 *   static void traced_sub_00012345(void) {
 *       fprintf(stderr, "[TRACE] sub_00012345 entered, eax=0x%08X\n", g_eax);
 *       sub_00012345();
 *       fprintf(stderr, "[TRACE] sub_00012345 returned, eax=0x%08X\n", g_eax);
 *   }
 *
 *   // Stub: skip a function entirely (return 0 in eax)
 *   static void stub_00067890(void) {
 *       g_eax = 0;
 *   }
 *
 *   // Fix: replace a broken lifted function with correct C
 *   static void fixed_sub_000ABCDE(void) {
 *       // Read arguments from stack/registers per calling convention
 *       uint32_t arg1 = g_ecx;
 *       uint32_t arg2 = MEM32(g_esp + 4);
 *       // ... correct implementation ...
 *       g_eax = result;
 *   }
 */
recomp_func_t recomp_lookup_manual(uint32_t xbox_va)
{
    /*
     * TODO: Add your overrides here. Examples:
     *
     * if (xbox_va == 0x00012345) return traced_sub_00012345;
     * if (xbox_va == 0x00067890) return stub_00067890;
     * if (xbox_va == 0x000ABCDE) return fixed_sub_000ABCDE;
     */

    (void)xbox_va;
    return (recomp_func_t)0;
}

/* ── ICALL failure logging ─────────────────────────────────── */

/*
 * Called when RECOMP_ICALL cannot resolve a target address.
 * This usually means one of:
 *   - A vtable dispatch to an address not in the dispatch table
 *   - A function pointer loaded from uninitialized or corrupt memory
 *   - A kernel thunk address that the bridge doesn't handle
 *
 * During early bring-up you will see many of these. Most are harmless
 * (the ICALL macro pops the dummy return address and continues).
 * Focus on the ones that cause crashes or incorrect behavior.
 */
void recomp_icall_fail_log(uint32_t va)
{
    /*
     * Rate-limited per target, reporting at 1, 10, 100 ...
     *
     * An unresolved target inside a loop is the normal case, not the rare
     * one: Mortal Kombat: Deadly Alliance produced 46843 of these for a
     * single address in one 30-second run, seventeen lines each. That buries
     * every other diagnostic in the log and says nothing the first report did
     * not. The progression is the useful part -- one line says a target was
     * never identified, a run of them says the title is stuck on it.
     */
    enum { SLOTS = 16 };
    static uint32_t seen[SLOTS];
    static uint64_t hits[SLOTS];
    static int count;
    int i;

    for (i = 0; i < count; i++)
        if (seen[i] == va)
            break;
    if (i == count) {
        if (count == SLOTS)
            return;
        seen[count] = va;
        hits[count] = 0;
        count++;
    }
    hits[i]++;
    {
        uint64_t n = hits[i];
        while (n >= 10 && n % 10 == 0)
            n /= 10;
        if (n != 1)
            return;
    }

    RECOMP_DIAG_LOCK();
    fprintf(stderr, "[ICALL] unresolved %starget 0x%08X -- %llu time(s) "
                    "(total calls: %llu)\n",
            g_icall_dispatch_form == 1 ? "call " :
            g_icall_dispatch_form == 2 ? "jump " : "",
            va, (unsigned long long)hits[i],
            (unsigned long long)g_icall_count);
    if (g_icall_dispatch_form == 2 && hits[i] == 1)
        fprintf(stderr, "  a jump, not a call: if this address is inside a "
                        "function rather than at its start, the guest is doing "
                        "its own control flow (a coroutine, a longjmp, or a "
                        "switch arm) and seeding it as a function will not "
                        "help\n");

    /*
     * Who called it. The lifted caller pushed its return address on the guest
     * stack, so code-range values above esp name the chain -- the same scan
     * the memory watchpoints use. It is a heuristic: stale return addresses
     * from earlier frames show up too, and the first entry is the reliable
     * one. It is still the difference between an address with no context and
     * a function to open, which is what an unresolved target needs.
     */
    {
        const uint8_t *stack = (const uint8_t *)g_xbox_mem_offset
                             + g_icall_saved_esp;
        int shown = 0;
        fprintf(stderr, "  callers:");
        for (i = 0; g_xbox_mem_offset && g_icall_saved_esp
                    && i < 160 && shown < 6; i++) {
            uint32_t v;
            memcpy(&v, stack + (size_t)i * 4, sizeof v);
            if (v >= g_xbox_code_lo && v < g_xbox_code_hi) {
                fprintf(stderr, "%s 0x%08X", shown ? " <-" : "", v);
                shown++;
            }
        }
        if (!shown)
            fprintf(stderr, " (none on the stack)");
        fprintf(stderr, "\n");
    }

    /* The recent-target ring buffer, once per address. What ran just before
     * an unresolved call is context for the first report and noise after. */
    if (hits[i] == 1) {
        fprintf(stderr, "  Recent ICALL targets:\n");
        for (i = 0; i < 16; i++) {
            int idx = (g_icall_trace_idx - 16 + i) & 15;
            if (g_icall_trace[idx])
                fprintf(stderr, "    [%2d] 0x%08X\n", i, g_icall_trace[idx]);
        }
    }
    RECOMP_DIAG_UNLOCK();
    fflush(stderr);
}
/* An indirect call whose target is not code: a null or wild function pointer.
 *
 * Skipping these is right -- calling a data address is worse -- but skipping
 * them *silently* is not. They almost always arrive inside a loop, so the
 * symptom is a hang with no output rather than a diagnosable null vtable call.
 *
 * Rate-limited per address: a spin can produce millions of these, and the
 * useful information is which addresses occur, not how often.
 */
void recomp_icall_not_code_log(uint32_t va, uint32_t saved_esp)
{
    /* A power of ten, because the rate limiter above only reaches this
     * function body at 1, 10, 100 ... and the verdict has to land on one of
     * those. A hundred thousand skips of one target is unambiguous: no title
     * makes progress through that. */
    enum { SLOTS = 16, SPIN_VERDICT = 100000 };
    static uint32_t seen[SLOTS];
    static uint64_t hits[SLOTS];
    static int count;
    static int said_it;   /* the verdict below is said once, not once per target */
    int i;

    for (i = 0; i < count; i++)
        if (seen[i] == va)
            break;
    if (i == count) {
        if (count == SLOTS)
            return;
        seen[count] = va;
        hits[count] = 0;
        count++;
    }
    hits[i]++;
    /* Report at 1, 10, 100, 1000 ... rather than once. A single line says a
     * wild pointer was skipped; the progression says it is being skipped in a
     * loop, which is the difference between a curiosity and the reason the
     * title is hung. */
    {
        uint64_t n = hits[i];
        while (n >= 10 && n % 10 == 0)
            n /= 10;
        if (n != 1)
            return;
    }
    {
        /* The call site, read off the guest stack. Without it the log
         * says a wild pointer was skipped but not by whom, and the
         * caller is the only thing that leads anywhere.
         *
         * It comes from the esp the dispatch macro captured, not from
         * g_esp. The lifted call site pushes its return address onto the
         * *local* esp and only syncs g_esp at certain points, so g_esp is
         * stale here -- it read 0 exactly when a null target most needed
         * explaining, which sent three rounds of Jet Set Radio Future
         * chasing inferences instead of a call site. saved_esp is the value
         * before that push, so the return address is the dword below it.
         *
         * Only for the call form. A tail jump pushes no return address, so
         * that dword is whatever the frame happened to leave there: Tony
         * Hawk's Pro Skater 2X reported "from 0x00000008" and then "from
         * 0x00000004" for the same million skipped calls, and both are
         * plainly not code. Printing a number that cannot be an address as
         * though it were the caller is worse than printing nothing, because
         * it is the one field a reader goes to next.
         *
         * So: name the form, and where the top of the stack cannot answer,
         * scan for code-range values the way the unresolved-target logger
         * above does. Stale return addresses from earlier frames come back
         * too and the first is the reliable one, but a list of real code
         * addresses is a place to start and 0x00000008 is not. */
        uint32_t caller = 0;
        if (g_icall_dispatch_form != 2 && saved_esp >= 4 && g_xbox_mem_offset)
            caller = *(const uint32_t *)((const uint8_t *)g_xbox_mem_offset
                                         + (saved_esp - 4));
        if (caller < g_xbox_code_lo || caller >= g_xbox_code_hi)
            caller = 0;
        RECOMP_DIAG_LOCK();
    fprintf(stderr, "[ICALL] target 0x%08X is not code -- skipped "
                        "%llu time(s) via a %s",
                va, (unsigned long long)hits[i],
                g_icall_dispatch_form == 2 ? "jump" : "call");
        if (caller)
            fprintf(stderr, " from 0x%08X", caller);
        fprintf(stderr, " (null or wild function pointer, at call #%llu)\n",
                (unsigned long long)g_icall_count);

        /* The stack scan, once per address: the same heuristic the
         * unresolved-target logger uses, and the only thing that names a
         * caller when the return address is not where it should be. */
        if (hits[i] == 1) {
            const uint8_t *stack = (const uint8_t *)g_xbox_mem_offset
                                 + saved_esp;
            int shown = 0, k;
            fprintf(stderr, "  callers:");
            for (k = 0; g_xbox_mem_offset && saved_esp
                        && k < 160 && shown < 6; k++) {
                uint32_t v;
                memcpy(&v, stack + (size_t)k * 4, sizeof v);
                if (v >= g_xbox_code_lo && v < g_xbox_code_hi) {
                    fprintf(stderr, "%s 0x%08X", shown ? " <-" : "", v);
                    shown++;
                }
            }
            if (!shown)
                fprintf(stderr, " (none on the stack)");
            fprintf(stderr, "\n");
        }

        /* RECOMP_ICALL_FATAL=1: fault here instead of skipping, so the crash
         * handler prints the guest call stack that reached this call.
         *
         * The caller printed above is read from the top of the guest stack,
         * which is right only when the lifted call site pushed a return
         * address there and nothing has since moved esp. When it reads 0 --
         * exactly the case where a null target most needs explaining -- the
         * line says a wild pointer was skipped and nothing about by whom. A
         * deliberate fault costs the run and buys the backtrace. */
        {
            static int fatal = -1;
            if (fatal < 0) {
                const char *v = getenv("RECOMP_ICALL_FATAL");
                fatal = v && *v && strcmp(v, "0") != 0;
            }
            if (fatal) {
                fprintf(stderr, "[ICALL] RECOMP_ICALL_FATAL: faulting here for "
                                "a backtrace\n");
                fflush(stderr);
                *(volatile int *)0 = 1;
            }
        }
    }

    /* Past a certain count this stops being a warning and becomes a verdict.
     *
     * A skipped call sets eax to 0 and returns. Zero is a fine answer for a
     * null function pointer in most code -- it reads as NULL, false, or
     * nothing -- but it is also S_OK, so in COM-shaped code a loop that
     * repeats while the result is non-negative can never leave. Panzer
     * Dragoon Orta hung exactly there, three billion skips in forty seconds,
     * with no frame ever presented.
     *
     * The value is deliberately left alone: there is no return value that is
     * right for both conventions, and guessing failure would break the
     * callers for which zero is correct. What can be fixed is the silence.
     * Say plainly that the title is hung, once, and say what to do about it.
     */
    if (hits[i] == SPIN_VERDICT && !said_it) {
        said_it = 1;
        fprintf(stderr,
            "[ICALL] ^^ this is a hang, not slow progress. One target has been\n"
            "        skipped %d times. The skip returns eax = 0, which is also\n"
            "        S_OK, so a loop testing for a non-negative result will\n"
            "        never exit. Try `py -3 -m tools.seed_from_log <log>` to\n"
            "        recover the target as a function, and read\n"
            "        docs/technical/memory-watchpoints.md for who wrote the\n"
            "        pointer. Set RECOMP_ICALL_SPIN_FATAL=1 to stop here\n"
            "        instead of spinning.\n", SPIN_VERDICT);
        fflush(stderr);
        if (getenv("RECOMP_ICALL_SPIN_FATAL")) {
            fprintf(stderr, "[ICALL] RECOMP_ICALL_SPIN_FATAL is set; exiting.\n");
            fflush(stderr);
            exit(3);
        }
    }
    RECOMP_DIAG_UNLOCK();
    fflush(stderr);
}


/* -- Online co-op: one step per frame on every machine -------------------- */

/*
 * Online co-op runs the whole game on every machine and sends only the
 * controllers (recompose src/kernel/recomp_lockstep.h), so every copy must
 * step the game by the same amount each frame. Future Perfect steps as
 * TimeSplitters 2 does (src/recomp_manual.c, ts2_frame_clock): its frame
 * clock (frame_clock, USA sub_001538C0) waits for its vblank counter to move,
 * then steps by the vblanks elapsed since the last frame, 1 at 60 fps and
 * clamped to 3. Two machines would step differently whenever one ran a frame
 * late. With lockstep on, the counter's reader (vblank_count, USA
 * sub_00022030) answers the lockstep tick instead, and frame_clock's entry is
 * the frame boundary where the tick advances and the controllers are
 * latched: every frame is one step everywhere.
 *
 * The state hashed each tick is the release's data section, named in
 * overrides.inc, less what is not game state (entries with no name).
 */
typedef struct FpStateRegion { uint32_t va, size; const char *name; } FpStateRegion;
extern void recomp_lockstep_ignore(uint32_t va, uint32_t size);
extern int recomp_lockstep_active(void);
extern void recomp_lockstep_frame(void);
extern uint32_t recomp_lockstep_tick(void);
extern void recomp_lockstep_add_region(uint32_t va, uint32_t size, const char *name);

/*
 * RECOMP_FP_MEMDUMP=<prefix> with RECOMP_FP_MEMDUMP_AT=<tick>,<tick>,...: guest
 * memory written at those lockstep ticks to <prefix>t<tick>.bin, in the
 * lockstep dump's format (py -m tools.lockstep dump), every mapped 64 KB of
 * RECOMP_FP_MEMDUMP_RANGE=<va>-<va> (default 0x00800000-0x04000000, past the
 * XBE's image to the top of RAM). TimeSplitters 2's ts2_memdump, for finding
 * where the game keeps what .data does not hold: the player, the camera.
 * A tool for finding things; nothing reads it back.
 */
extern int xbox_guest_range_mapped(uint32_t va, uint32_t bytes);

static void fp_memdump(uint32_t tick)
{
    static int ready, n;
    static uint32_t at[32], lo = 0x00800000u, hi = 0x04000000u;
    static const char *prefix;
    char path[512];
    FILE *f;
    uint32_t va, runs = 0;
    int i;

    if (!ready) {
        const char *v = getenv("RECOMP_FP_MEMDUMP_AT"), *r = getenv("RECOMP_FP_MEMDUMP_RANGE");

        ready = 1;
        prefix = getenv("RECOMP_FP_MEMDUMP");
        while (prefix && v && *v && n < 32) {
            at[n++] = (uint32_t)strtoul(v, (char **)&v, 10);
            if (*v == ',')
                v++;
            else
                break;
        }
        if (r && *r) {
            lo = (uint32_t)strtoul(r, (char **)&r, 0);
            if (*r == '-')
                hi = (uint32_t)strtoul(r + 1, NULL, 0);
        }
    }
    for (i = 0; i < n && at[i] != tick; i++)
        ;
    if (i == n)
        return;
    snprintf(path, sizeof path, "%st%u.bin", prefix, tick);
    f = fopen(path, "wb");
    if (!f)
        return;
    for (va = lo; va < hi; ) {
        uint32_t end = va;

        while (end < hi && xbox_guest_range_mapped(end, 0x10000u))
            end += 0x10000u;
        if (end > va) {
            runs++;
            va = end;
        } else {
            va += 0x10000u;
        }
    }
    fwrite("LSDUMP1\n", 1, 8, f);
    fwrite(&runs, 4, 1, f);
    for (va = lo; va < hi; ) {
        uint32_t end = va;

        while (end < hi && xbox_guest_range_mapped(end, 0x10000u))
            end += 0x10000u;
        if (end > va) {
            uint32_t hdr[2] = { va, end - va };
            char name[32] = "heap";

            fwrite(hdr, 4, 2, f);
            fwrite(name, 1, 32, f);
            fwrite((const void *)((uintptr_t)va + g_xbox_mem_offset), 1, end - va, f);
            va = end;
        } else {
            va += 0x10000u;
        }
    }
    fclose(f);
    fprintf(stderr, "[FP] memory dump at tick %u: %s\n", tick, path);
}

static void fp_coop_frame_start(void);     /* online co-op's views, below */
static void fp_weapon_keys_frame(void);    /* the number keys, below */
static void fp_menu_mouse_frame(void);     /* the mouse in the menus, below */
static void fp_wheel_install(void);        /* the wheel, below */

static void fp_frame_clock(void (*gen)(void), const FpStateRegion *state)
{
    static int named;

    if (recomp_lockstep_active()) {
        if (!named) {
            named = 1;
            for (; state->size; state++)
                if (state->name)
                    recomp_lockstep_add_region(state->va, state->size, state->name);
                else
                    recomp_lockstep_ignore(state->va, state->size);
        }
        recomp_lockstep_frame();
        fp_memdump(recomp_lockstep_tick());
    }
    fp_coop_frame_start();
    fp_weapon_keys_frame();
    fp_wheel_install();
    fp_menu_mouse_frame();
    gen();
}

static void fp_vblank_count(void (*gen)(void))
{
    if (recomp_lockstep_active()) {
        g_eax = recomp_lockstep_tick();
        g_esp += 4;                        /* ret */
        return;
    }
    gen();
}

/*
 * The loading screen has a thread of its own (USA sub_00156CB0): while the
 * frame's thread loads, it draws and presents the loading screen once a
 * vblank, spinning on vblank_count until the count moves, and fades it out;
 * the stop (sub_00156840) busy-waits for that fade before it ends the thread
 * and waits for it. Under lockstep the count is the tick, which no load
 * moves, so the thread would spin holding the guest lock and the load would
 * never finish; and a thread drawing on the host's clock would touch the
 * game at a different moment on every machine. So in a co-op session the
 * game is never let start it (loading_screen_start, sub_00156D80, returns
 * before it writes anything): the stops find it stopped and return, and a
 * loading screen holds still on every machine alike.
 */
static void fp_loading_screen_start(void (*gen)(void))
{
    if (recomp_lockstep_active()) {
        g_esp += 4;                        /* ret */
        return;
    }
    gen();
}

/*
 * No look-spring with a mouse (as TimeSplitters 2's ts2_look_spring). The
 * profile's Auto Lookahead (Settings > Controls, on in a new profile) levels
 * the view while the player walks with no look input: the look step
 * (look_step, USA sub_0025D520) takes a share of the pitch each frame while
 * bit 3 of byte 2 of the profile's controls is set. Right for a stick,
 * which springs back to the middle; wrong for a mouse, which stays where it
 * was put: a look up or down was pulled back to the horizon within a second
 * of walking. With mouse look on, the bit is cleared while that step runs
 * and put back straight after, so the profile -- and what the game saves of
 * it -- is untouched. Every machine in a co-op session must do the same, so
 * mouse_look is one of the settings a session checks (src/main.c).
 */
extern int recomp_config_bool(const char *env_name, const char *key, int def);
/* recompose src/hle/hle_input.h: the look for a guest port this frame, in
 * degrees, x right and y down, sensitivity and invert applied; under online
 * co-op the latched one. */
extern int recomp_input_look(unsigned port, float *dx_deg, float *dy_deg);

/*
 * Native mouse look (as TimeSplitters 2's ts2_mouse_look): the mouse turns
 * the player as an angle rather than through the right stick, which the
 * game accelerates and which Inverse Look turns over. The look step keeps
 * the player's look as degrees in its look state: yaw at +0x100 (0 to 360),
 * pitch at +0x104 (held within the limit at pitch_limit). After the game's
 * own step -- a pad's stick still turns as the game turns it -- the
 * controller's mouse look is added: the look state's controller is the
 * game's own mapping, its id (+0) through the table at port_map, or the id
 * itself while port_direct is set.
 */
typedef struct FpLook {
    uint32_t state_ptr;      /* the look state being stepped, a pointer */
    uint32_t controls_off;   /* the profile's controls, a pointer in the state */
    uint32_t yaw_off, pitch_off;
    uint32_t pitch_limit;    /* a float */
    uint32_t port_map, port_direct;
    uint32_t camera_ptr;     /* the player's camera while it is stepped, a pointer */
    uint32_t angle_off;      /* the camera's angle the zoom aims for, a float */
} FpLook;

#define FP_M32(va) (*(volatile uint32_t *)((uintptr_t)(uint32_t)(va) + g_xbox_mem_offset))
#define FP_MF(va)  (*(volatile float *)((uintptr_t)(uint32_t)(va) + g_xbox_mem_offset))

/*
 * What the mouse does, decided each frame (fp_frame_clock) from what the
 * frame before did, and held a quarter of a second (15 frames) before it
 * changes:
 *
 *   on foot   a player was controlled and controller 1's took the look step
 *             (sub_0025D520): native mouse look, as before;
 *   stick     a player was controlled but controller 1's not on foot -- the
 *             look state's other control modes, which the dispatcher
 *             (sub_000D5C70) sends to their own steps and which read the
 *             right stick themselves (vehicles, mounted guns, remote
 *             devices): the mouse moves the right stick, as mouse look does
 *             in a title without native look, its buttons as bound;
 *   mapmaker  no player controlled but MapMaker's editor ran (sub_00306460,
 *             which reads the right stick every frame to pan, turn and zoom
 *             the grid, and runs behind MapMaker's own screens too):
 *             MapMaker draws a cursor of its own and moves it with the left
 *             stick, A choosing under it, so the mouse moves the left stick,
 *             its left button is A and its right B, the wheel up and down,
 *             with the pointer kept (recompose recomp_mouse_look_left,
 *             recomp_mouse_pad_buttons); the grid's view is on I J K L;
 *   menu      none of those: the front end and every submenu, the pause and
 *             SCORES screens, a level's results and cutscenes. The pointer
 *             is shown and the mouse works the menu (left button A, right B,
 *             the wheel up and down; recompose hle_window_title_menu), as
 *             TimeSplitters 2's.
 *
 * Before, the mouse stayed captured as native look everywhere: in the menus
 * its buttons were still fire and aim and it did nothing there, and whatever
 * read the right stick outside the look step got nothing from it (found by
 * the Mac session, logging every right-stick read: on foot only the look
 * step reads it; MapMaker's editor and the dispatched modes read it
 * themselves). Online each machine decides for its own controller from the
 * game, which is the same on both, and what it sends is the latched pad.
 */
extern void hle_window_title_menu(int on);
extern void recomp_mouse_look_native(int on);
extern void recomp_mouse_look_left(int on);
extern void recomp_mouse_pad_buttons(int on);
static volatile int g_fp_frame_play, g_fp_frame_look, g_fp_frame_editor;
/* A player's view this frame was only part of the screen (a split screen:
 * fp_viewport_rect, from the player's pass). */
static volatile int g_fp_frame_partial;

/*
 * The scissors, as TimeSplitters 2's (ts2_present), but for the world only.
 * Future Perfect clips each room it sees through a gap -- a doorway, a cleft
 * in a canyon wall -- to the gap's rectangle on screen, and scissors the
 * rest of the world to the whole screen, millions of draws a minute in
 * play. In frame interpolation's in-between frames the rectangles are where
 * the newer frame had them, so while the view turned fast a slit of sky
 * showed through a solid rock wall and slabs near the screen's edge were
 * cut off, at 4x most of all; and the whole-screen one, 0,0-639,479, leaves
 * the picture's last column and row dark. Its HUD uses them too, though,
 * unlike TimeSplitters 2's: the weapon-mode panel wipes in through one, and
 * without it popped in whole (a replayed walk through 2401, every scissored
 * draw of a frame logged: the world's test depth, the HUD's do not). So off
 * for the draws that test depth (recompose XBOX_D3D8_SCISSORS_OFF_WORLD),
 * and only for a frame of play whose every player's view is the whole
 * screen: the menus' list boxes and MapMaker need theirs, and a split
 * screen keeps each view to its part of the screen with one.
 */
extern void xbox_D3D8SetScissorsOff(int mode);   /* recompose d3d8_xbox.h */
#define FP_SCISSORS_KEEP    0
#define FP_SCISSORS_IN_PLAY 3                     /* XBOX_D3D8_SCISSORS_OFF_WORLD */

static void fp_scissors_frame(int played, int partial)
{
    static int mode = -1;
    int want = played && !partial ? FP_SCISSORS_IN_PLAY : FP_SCISSORS_KEEP;

    if (want != mode) {
        mode = want;
        xbox_D3D8SetScissorsOff(want);
    }
}

static void fp_menu_mouse_frame(void)
{
    enum { MOUSE_LOOK, MOUSE_STICK, MOUSE_MAPMAKER, MOUSE_MENU };
    static int quiet_play = 1000, quiet_look = 1000, quiet_editor = 1000;
    static int shown = -1, said;
    int mode;

    fp_scissors_frame(g_fp_frame_play, g_fp_frame_partial);
    quiet_play = g_fp_frame_play ? 0 : quiet_play < 1000 ? quiet_play + 1 : quiet_play;
    quiet_look = g_fp_frame_look ? 0 : quiet_look < 1000 ? quiet_look + 1 : quiet_look;
    quiet_editor = g_fp_frame_editor ? 0 : quiet_editor < 1000 ? quiet_editor + 1 : quiet_editor;
    g_fp_frame_play = g_fp_frame_look = g_fp_frame_editor = g_fp_frame_partial = 0;
    if (quiet_play < 15)
        mode = quiet_look < 15 ? MOUSE_LOOK : MOUSE_STICK;
    else
        mode = quiet_editor < 15 ? MOUSE_MAPMAKER : MOUSE_MENU;
    if (mode != shown) {
        shown = mode;
        /* Native look off only where the mouse moves a stick: in the menus
         * it stays on, or the mouse would move the right stick there too. */
        recomp_mouse_look_native(mode != MOUSE_STICK && mode != MOUSE_MAPMAKER);
        recomp_mouse_look_left(mode == MOUSE_MAPMAKER);
        recomp_mouse_pad_buttons(mode == MOUSE_MAPMAKER);
        hle_window_title_menu(mode == MOUSE_MENU);
        if (said < 12) {
            said++;
            fprintf(stderr, "[FP] %s (tick %u)\n",
                    mode == MOUSE_MENU ? "menus: the mouse works the menu"
                    : mode == MOUSE_STICK ? "not on foot: the mouse moves the right stick"
                    : mode == MOUSE_MAPMAKER ? "MapMaker: the mouse moves its cursor, the buttons choose"
                    : "on foot: the mouse looks", recomp_lockstep_tick());
        }
    }
}

/* A player is controlled this frame, in whatever mode (the dispatcher). */
static void fp_control_step(void (*gen)(void))
{
    g_fp_frame_play = 1;
    gen();
}

/* MapMaker's editor ran this frame. */
static void fp_editor_step(void (*gen)(void))
{
    g_fp_frame_editor = 1;
    gen();
}

/* Whether the keyboard and mouse's player is aiming a weapon that zooms
 * (fp_zoom_state, after the FOV code below), for the wheel. */
static volatile int g_fp_p1_zoom;
static void fp_zoom_state(uint32_t cam, uint32_t angle_off);

static void fp_look_step(void (*gen)(void), const FpLook *l)
{
    static int mouse = -1;
    volatile uint8_t *flags = NULL;
    uint8_t was = 0;
    uint32_t p, c;
    float dx, dy;

    if (mouse < 0)
        mouse = recomp_config_bool("RECOMP_MOUSE_LOOK", "mouse_look", 0);
    p = FP_M32(l->state_ptr);
    if (!(p >= 0x10000u && p < 0x84000000u)) {
        gen();
        return;
    }
    if (mouse) {
        c = FP_M32(p + l->controls_off);
        if (c >= 0x10000u && c < 0x84000000u) {
            flags = (volatile uint8_t *)((uintptr_t)(c + 2u) + g_xbox_mem_offset);
            was = *flags;
            *flags = (uint8_t)(was & ~0x08u);
        }
    }
    gen();
    if (flags)
        *flags = was;
    g_fp_frame_play = 1;                   /* a player was updated: play (fp_menu_mouse_frame) */
    {
        uint32_t id = FP_M32(p);
        uint32_t port = FP_M32(l->port_direct) ? id : (id < 16u ? FP_M32(l->port_map + 4u * id) : 4u);

        if (port == 0u) {                  /* the keyboard and mouse's player, on foot */
            g_fp_frame_look = 1;
            fp_zoom_state(FP_M32(l->camera_ptr), l->angle_off);
        }
    }
    if (mouse) {
        uint32_t id = FP_M32(p), port;

        port = FP_M32(l->port_direct) ? id : (id < 16u ? FP_M32(l->port_map + 4u * id) : 4u);
        if (port < 4u && recomp_input_look(port, &dx, &dy)) {
            float yaw = FP_MF(p + l->yaw_off) - dx;
            float pitch = FP_MF(p + l->pitch_off) - dy;   /* dy is down the screen */
            float limit = FP_MF(l->pitch_limit);

            while (yaw >= 360.0f)
                yaw -= 360.0f;
            while (yaw < 0.0f)
                yaw += 360.0f;
            if (limit > 0.0f && limit < 90.0f) {
                if (pitch > limit)
                    pitch = limit;
                if (pitch < -limit)
                    pitch = -limit;
            }
            FP_MF(p + l->yaw_off) = yaw;
            FP_MF(p + l->pitch_off) = pitch;
        }
    }
}

/*
 * The field of view (the toolkit's fov setting: the launcher's Graphics and
 * the Esc menu's slider). base_fov (USA sub_000CB3B0) is the player's
 * vertical field of view in degrees, which the look step and the camera and
 * culling code ask for: the game's 55, or another constant in one state of
 * the player. When it answers 55 the chosen angle replaces it, on the x87
 * stack where the function leaves it; any other answer is left as the game
 * made it. 0 -- the default -- is the game's own. The setting changes what
 * is culled as well as what is drawn, so an online co-op session checks it
 * (src/main.c, as TimeSplitters 2's).
 */
extern int hle_fov(void);

/* The game's two angles: 55 (its field of view) and 45 (the one it gives a
 * player with +0x254 == 0 and +0x258 == 1, which every player in split
 * screen is: Arcade with two or more, story co-op). */
#define FP_FOV_BASE_VA  0x004785CCu
#define FP_FOV_OTHER_VA 0x00478900u

static float fp_fov_const(uint32_t va)
{
    return *(volatile float *)((uintptr_t)va + g_xbox_mem_offset);
}

/* An angle the game chose, as the chosen field of view makes it: 55
 * becomes the chosen angle, 45 widens by as much (tan(new/2) = tan(45/2) *
 * tan(fov/2) / tan(55/2)), anything else -- a scope's zoom, a cutscene's --
 * is left as it is. */
static float fp_fov_widen(float angle)
{
    int fov = hle_fov();
    float base = fp_fov_const(FP_FOV_BASE_VA), other = fp_fov_const(FP_FOV_OTHER_VA);
    double r;

    if (fov <= 0 || (float)fov == base || !(base > 0.0f))
        return angle;
    if (angle == base)
        return (float)fov;
    if (angle != other)
        return angle;
    r = tan((double)fov * 3.14159265358979 / 360.0) / tan((double)base * 3.14159265358979 / 360.0);
    return (float)(2.0 * atan(tan((double)other * 3.14159265358979 / 360.0) * r) * 180.0 / 3.14159265358979);
}

/* How much wider a camera showing `angle` is than the game's would be, for
 * the first-person view model, which should stay the size the game drew it.
 * `base` is the camera's own angle (player+0x390): the game derives its
 * other angles from it in proportion -- aiming is 0.55 of it (30.25 at the
 * game's 55, 44 at a chosen 80) -- and eases between them. When the base is
 * one the field of view widened (from 55, or 45 in split screen), the angle
 * the game would show now is angle * game base / base, and k is the ratio of
 * the two tangents: tan(fov/2) / tan(55/2) at rest, a little less while
 * aiming. Any other base (no field of view chosen, a cutscene's camera) is 1. */
float fp_fov_view_k(float angle, float base_now)
{
    int fov = hle_fov();
    float base = fp_fov_const(FP_FOV_BASE_VA), other = fp_fov_const(FP_FOV_OTHER_VA), game;

    if (fov <= 0 || (float)fov == base || !(base > 0.0f) || !(angle > 0.0f) || angle >= 180.0f)
        return 1.0f;
    if (base_now == fp_fov_widen(base))
        game = base;
    else if (base_now == fp_fov_widen(other))
        game = other;
    else
        return 1.0f;
    return (float)(tan((double)angle * 3.14159265358979 / 360.0) /
                   tan((double)angle * game / base_now * 3.14159265358979 / 360.0));
}

/*
 * The mouse wheel (as TimeSplitters 2's ts2_wheel_filter): aiming a weapon
 * that zooms, it zooms in (away) and out (towards), as the d-pad up and down
 * do; otherwise it changes weapon, as the d-pad left and right do. Future
 * Perfect's own d-pad works the same way: up and down change the weapon's
 * mode when not aiming (a pair of pistols to the single scoped one) and zoom
 * while aiming. Aiming a weapon that zooms is the camera's angle (+0x388,
 * where the zoom is going) below the angle at rest -- the game's 55 or split
 * screen's 45, as the field of view setting widened them -- by more than a
 * little: the scoped pistol aims at 30.25 and the d-pad then takes it down a
 * degree at a time (24.25 and 23.25 in an Arcade match); a pair of pistols,
 * which does not zoom, leaves it at rest. The state is the keyboard and
 * mouse's player's (controller 1), read each time that player is stepped;
 * the wheel acts on it as the frame's pad is sampled, and that pad is what
 * is latched, so online every machine acts on the same one.
 */
typedef struct { uint16_t wButtons; uint8_t bAnalogButtons[8]; int16_t sThumb[4]; } FpGamepad;
extern void recomp_bindings_set_wheel_filter(void (*fn)(int wheel, FpGamepad *pad));

static void fp_zoom_state(uint32_t cam, uint32_t angle_off)
{
    float a, rest, r55, r45;

    if (!(cam >= 0x10000u && cam < 0x84000000u)) {
        g_fp_p1_zoom = 0;
        return;
    }
    a = FP_MF(cam + angle_off);
    r55 = fp_fov_widen(fp_fov_const(FP_FOV_BASE_VA));
    r45 = fp_fov_widen(fp_fov_const(FP_FOV_OTHER_VA));
    rest = r45 > 1.0f && r45 < r55 ? r45 : r55;
    g_fp_p1_zoom = a > 1.0f && rest > 1.0f && a < rest * 0.98f;
}

static void fp_wheel_filter(int wheel, FpGamepad *pad)
{
    if (!wheel)
        return;
    if (g_fp_p1_zoom)
        pad->wButtons |= wheel > 0 ? 0x0001 : 0x0002;   /* d-pad up: in; down: out */
    else
        pad->wButtons |= wheel > 0 ? 0x0004 : 0x0008;   /* d-pad left, right: weapon */
}

/* Installed at the first frame: the wheel's filter, and the dead zone Future
 * Perfect's stick reads have -- 0.25 of a push, the first float of each
 * pad's record (0x006B93D0 for controller 1, read in MapMaker), which
 * sub_00042970 takes off every axis -- so the mouse, where it moves a stick
 * (MapMaker's cursor, the modes off foot), is lifted past it (recompose
 * recomp_mouse_stick_dead_zone): a slow movement moved MapMaker's cursor not
 * at all before (a push of 0.14) and only a fast one did (0.53). */
extern void recomp_mouse_stick_dead_zone(float dz);

static void fp_wheel_install(void)
{
    static int done;

    if (!done) {
        done = 1;
        recomp_bindings_set_wheel_filter(fp_wheel_filter);
        recomp_mouse_stick_dead_zone(0.25f);
    }
}

static void fp_base_fov(void (*gen)(void), uint32_t base_va)
{
    (void)base_va;
    gen();
    g_fp_stack[g_fp_top & 7u] = (double)fp_fov_widen((float)g_fp_stack[g_fp_top & 7u]);
}

/*
 * The player's camera angle is a set of fields: +0x390 its base, +0x38C the
 * aiming angle (0.55 of the base), +0x388 the one it is heading for, and
 * +0x384 the one shown, which sub_0025E650 eases toward +0x388 and the
 * camera and culling read every frame. base_fov is only one of its writers (camera_fov, sub_00259DF0,
 * when the player's view mode changes). Two copies of base_fov's own test
 * are inlined where a player is set up, and write 55 or 45 there directly:
 * player_reset (sub_000CC720(player, mode), all four) at every spawn, and
 * player_place (sub_000CBD10(player, ...), +0x388). Without these the chosen
 * field of view took hold only at the player's first view change, and in
 * split screen not at all. Each is followed by the same widening, on the
 * fields it wrote, of the player its first argument names.
 */
static void fp_player_fov(void (*gen)(void), uint32_t first, uint32_t count)
{
    uint32_t pl = *(volatile uint32_t *)((uintptr_t)g_esp + 4u + g_xbox_mem_offset);
    uint32_t i;

    gen();
    if (!pl || hle_fov() <= 0)
        return;
    for (i = 0; i < count; i++) {
        volatile float *a = (volatile float *)((uintptr_t)pl + first + 4u * i + g_xbox_mem_offset);
        *a = fp_fov_widen(*a);
    }
}

/*
 * The weapon in hand at a wider field of view. The hands and the weapon are
 * drawn through the world's projection, so with the view widened past the
 * game's they shrank and drew further off. The object draw (USA
 * sub_000A2740(object)) knows them: an object whose layer (+0x34) is 0xCA + a
 * player is that player's first-person layer -- the hands, the weapon --
 * where the world's are under 0xC8, the sky 0xCF. The muzzle flash is not an
 * object but an effect (effect_draw, sub_00111FC0(effect)), one the effects'
 * pass draws in camera space (bit 0x10 of its flags, +4: the pass puts the
 * camera-space view at 0x007A5900 in place for it, sub_00112120) -- found in
 * an Arcade match at FOV 80, where the gun was put right and its flash came
 * out smaller and nearer the middle, apart from the muzzle. While either is
 * drawn, and while the camera's base ([0x007B0CC0] +0x390) is one the
 * setting widened (fp_fov_view_k), the renderer draws it tan(shown/2) /
 * tan(game's/2) times larger -- tan(fov/2) / tan(55/2) at rest, a little
 * less while aiming -- about the middle of the camera's view (recompose
 * xbox_D3D8SetViewModelZoom): as large, and where, the game's own angle drew
 * it. The middle is the camera's viewport's (+0x224, laid out by
 * viewport_rect), not Direct3D's: split screen keeps a viewport of the whole
 * screen and puts each player in a half through the projection, and about
 * the screen's middle the second player's pistols went off its bottom edge.
 * Any other angle the game makes -- aiming in, a narrower one of its own --
 * is drawn as the game made it.
 */
extern void xbox_D3D8SetViewModelZoom(float k, float cx, float cy);

typedef struct FpViewModel {
    uint32_t camera_ptr, fov_off;  /* the current camera, the angle it shows */
    uint32_t base_off;             /* the camera's base angle, which the others follow */
    uint32_t viewport_off;         /* the camera's viewport, viewport_rect's */
    uint32_t vp_x0, vp_x1, vp_y0, vp_y1; /* its corners, inclusive pixels */
    uint32_t layer_off, layer_lo, layer_hi; /* an object's layer, the players' */
    uint32_t effect_flags, effect_camera_space; /* an effect's flags, the bit */
} FpViewModel;

static float g_fp_view_zoom = 1.0f, g_fp_view_cx = -1.0f, g_fp_view_cy = -1.0f;

/* Run gen with the view model's zoom for the current camera. */
static void fp_view_zoomed(void (*gen)(void), const FpViewModel *m)
{
    uint32_t cam = FP_M32(m->camera_ptr), vp;
    float k = 1.0f, cx = -1.0f, cy = -1.0f;
    float was = g_fp_view_zoom, was_cx = g_fp_view_cx, was_cy = g_fp_view_cy;

    if (cam >= 0x10000u && cam < 0x84000000u) {
        k = fp_fov_view_k(FP_MF(cam + m->fov_off), FP_MF(cam + m->base_off));
        vp = cam + m->viewport_off;
        cx = (float)((int32_t)FP_M32(vp + m->vp_x0) + (int32_t)FP_M32(vp + m->vp_x1) + 1) * 0.5f;
        cy = (float)((int32_t)FP_M32(vp + m->vp_y0) + (int32_t)FP_M32(vp + m->vp_y1) + 1) * 0.5f;
    }
    if (k == was && (k == 1.0f || (cx == was_cx && cy == was_cy))) {
        gen();
        return;
    }
    g_fp_view_zoom = k;
    g_fp_view_cx = cx;
    g_fp_view_cy = cy;
    xbox_D3D8SetViewModelZoom(k, cx, cy);
    gen();
    g_fp_view_zoom = was;
    g_fp_view_cx = was_cx;
    g_fp_view_cy = was_cy;
    xbox_D3D8SetViewModelZoom(was, was_cx, was_cy);
}

static void fp_object_draw(void (*gen)(void), const FpViewModel *m)
{
    uint32_t obj = FP_M32(g_esp + 4), layer;

    if (hle_fov() <= 0 || obj < 0x10000u || obj >= 0x84000000u) {
        gen();
        return;
    }
    layer = FP_M32(obj + m->layer_off);
    if (layer < m->layer_lo || layer >= m->layer_hi)
        gen();
    else
        fp_view_zoomed(gen, m);
}

static void fp_effect_draw(void (*gen)(void), const FpViewModel *m)
{
    uint32_t fx = FP_M32(g_esp + 4);

    if (hle_fov() <= 0 || fx < 0x10000u || fx >= 0x84000000u ||
        !(FP_M32(fx + m->effect_flags) & m->effect_camera_space))
        gen();
    else
        fp_view_zoomed(gen, m);
}

/*
 * Online co-op: each player has the whole screen (as TimeSplitters 2's,
 * src/recomp_manual.c, and GoldenEye's network co-op). Both machines run the
 * whole two-player game, so both lay it out alike: every player's camera is
 * laid out as the whole screen, as in one-player play, on both machines --
 * the game is then the same on both. Each machine still runs every player's
 * pass, as the game needs, and draws only its own player's: the renderer
 * leaves out every draw and clear made while the game's current viewport is
 * the other player's camera or HUD (xbox_D3D8SetDrawFilter).
 *
 * Future Perfect lays a viewport out with viewport_rect(vp, x0, y0, x1, y1)
 * (USA sub_00055D90; the corners at +0/+4 and +0x14/+0x18, the middles and
 * half-sizes after them, from which the projection and the scissor are
 * made). The cameras' are laid out when a level is set up, by the camera
 * layout switch on the number of players (sub_0025A570: one, the whole
 * screen; two, player 1 the top half and player 2 the bottom; three or
 * four, quarters); each player's pass points the current-viewport word at
 * that player's camera's (camera + 0x224), and every frame lays the
 * player's HUD viewport out from it (sub_002F2FF0, from pass_caller). In a
 * level's intro both players watch player 1's camera, laid out whole
 * (0x000CB1B9): a frame with fewer than two passes is shown as the game
 * shows it.
 *
 *   coop_view = own (default) | split          [RECOMP_COOP_VIEW]
 *   RECOMP_FP_VIEW_PORT=0|1  plays a local game as that player would see it
 *                            online (the layout changes, so a replay of a
 *                            recording made without it can go its own way)
 *   RECOMP_FP_VPLOG=<tick>   viewport_rect's calls from that frame on, 400
 *                            lines (RECOMP_FP_VPLOG_SKIP=<va>,... leaves
 *                            out those return addresses)
 */
extern int recomp_lockstep_local_guest_port(void);
extern const char *recomp_config_lookup(const char *env_name, const char *key);
extern void xbox_D3D8SetDrawFilter(int (*keep)(void));

typedef struct FpViews {
    uint32_t current_vp;         /* the game's current-viewport word */
    uint32_t via_current;        /* sub_00056050's call: lays out the current one */
    uint32_t pass_caller;        /* each player's HUD viewport, every frame */
    uint32_t split[2];           /* the camera layout's two-player halves */
    uint32_t shared_caller;      /* one camera laid out whole for both to watch */
    uint32_t screen_w, screen_h; /* the screen's size, words */
    uint32_t state_ptr, port_map, port_direct;   /* as FpLook's */
} FpViews;

/* This frame's passes, and the other player's viewports, which the next
 * frame leaves undrawn. */
static struct { uint32_t port, camera_vp, hud_vp; } g_fp_pass[2];
static int g_fp_passes;
static uint32_t g_fp_other_camera, g_fp_other_hud;
/* The camera the game has laid out whole for both players to watch (a
 * level's intro), until it splits the screen again: 0 when none. */
static uint32_t g_fp_shared_camera;
static const FpViews *g_fp_views;

static int fp_coop_full_views(void)
{
    static int on = -1;

    if (on < 0) {
        const char *v = recomp_config_lookup("RECOMP_COOP_VIEW", "coop_view");
        const char *t = getenv("RECOMP_FP_VIEW_PORT");

        on = !(v && strcmp(v, "split") == 0) &&
             (recomp_lockstep_local_guest_port() >= 0 || (t && *t));
    }
    return on;
}

/* This machine's player: online, the session's; for a local check,
 * RECOMP_FP_VIEW_PORT. -1 when every pass is drawn. */
static int fp_coop_own_port(void)
{
    static int test_port = -2;
    int port = recomp_lockstep_local_guest_port();

    if (test_port == -2) {
        const char *t = getenv("RECOMP_FP_VIEW_PORT");

        test_port = t && *t ? atoi(t) : -1;
    }
    if (port < 0)
        port = test_port;
    return port >= 0 && port <= 1 ? port : -1;
}

/* The frame's one clear. Split screen clears the whole screen once a frame,
 * at the start of the first player's pass (with that player's camera
 * current), and the second player's pass draws over it with no clear of its
 * own. Left out with the first player's draws, the second player's picture
 * kept the last frame's depth, its level failed the depth test, and only the
 * sky and a few moved pieces showed (the Mac session, live: player 2's view
 * was all sky; tick 5,600 of the Arcade recording: one clear, then 157 of
 * player 1's draws, 111 of player 2's, 44 and 58). So the other player's
 * clears are kept until this player's own pass has begun, and left out only
 * after, when they would clear its picture. */
extern int xbox_D3D8FilterAsksClear(void);
static uint32_t g_fp_own_camera, g_fp_own_hud;
static int g_fp_own_begun;

static int fp_coop_keep_draw(void)
{
    uint32_t cur;

    if (!g_fp_other_camera)
        return 1;
    cur = FP_M32(g_fp_views->current_vp);
    if (cur == g_fp_own_camera || cur == g_fp_own_hud)
        g_fp_own_begun = 1;
    if (cur != g_fp_other_camera && cur != g_fp_other_hud)
        return 1;
    return xbox_D3D8FilterAsksClear() && !g_fp_own_begun;
}

/* At a frame's start (fp_frame_clock): whose pass this frame leaves undrawn,
 * from the last frame's. Only when the last frame had this player's pass and
 * another's, each its own camera, and neither the one the game shows both
 * players; otherwise this machine shows what the game shows. */
static void fp_coop_frame_start(void)
{
    int own = fp_coop_own_port(), i;

    g_fp_other_camera = g_fp_other_hud = 0;
    g_fp_own_camera = g_fp_own_hud = 0;
    g_fp_own_begun = 0;
    if (own >= 0 && g_fp_passes == 2 && g_fp_pass[0].camera_vp != g_fp_pass[1].camera_vp &&
        g_fp_pass[0].port != g_fp_pass[1].port &&
        g_fp_pass[0].camera_vp != g_fp_shared_camera && g_fp_pass[1].camera_vp != g_fp_shared_camera)
        for (i = 0; i < 2; i++)
            if (g_fp_pass[i].port == (uint32_t)own) {
                g_fp_own_camera = g_fp_pass[i].camera_vp;
                g_fp_own_hud = g_fp_pass[i].hud_vp;
                g_fp_other_camera = g_fp_pass[1 - i].camera_vp;
                g_fp_other_hud = g_fp_pass[1 - i].hud_vp;
            }
    g_fp_passes = 0;
}

static uint32_t fp_parse_list(const char *v, uint32_t *out, int max)
{
    int n = 0;

    while (v && *v && n < max) {
        out[n++] = (uint32_t)strtoul(v, (char **)&v, 16);
        if (*v == ',')
            v++;
        else
            break;
    }
    return (uint32_t)n;
}

static void fp_viewport_rect(void (*gen)(void), const FpViews *fv)
{
    static int ready, said;
    static long log_from = -1;
    static uint32_t skip[16], nskip;
    uint32_t from = FP_M32(g_esp), from2 = from == fv->via_current ? FP_M32(g_esp + 0x18) : 0u;
    uint32_t vp = FP_M32(g_esp + 4);
    int x0 = (int)FP_M32(g_esp + 8), y0 = (int)FP_M32(g_esp + 12);
    int x1 = (int)FP_M32(g_esp + 16), y1 = (int)FP_M32(g_esp + 20);
    uint32_t i;

    if (!ready) {
        const char *v = getenv("RECOMP_FP_VPLOG");

        ready = 1;
        g_fp_views = fv;
        log_from = v && *v ? atol(v) : -1;
        nskip = fp_parse_list(getenv("RECOMP_FP_VPLOG_SKIP"), skip, 16);
    }
    for (i = 0; i < nskip && skip[i] != from && skip[i] != from2; i++)
        ;
    if (log_from >= 0 && said < 400 && i == nskip && recomp_lockstep_tick() >= (uint32_t)log_from) {
        said++;
        fprintf(stderr, "[FP-VP] tick %u from 0x%08X via 0x%08X vp 0x%08X %d,%d-%d,%d current 0x%08X\n",
                recomp_lockstep_tick(), from, from2, vp, x0, y0, x1, y1, FP_M32(fv->current_vp));
    }
    if (fp_coop_full_views()) {
        static int told;

        if (!told++) {
            if (fp_coop_own_port() >= 0)
                xbox_D3D8SetDrawFilter(fp_coop_keep_draw);
            fprintf(stderr, "[FP] online co-op: every player's view laid out as the whole "
                    "screen%s\n", fp_coop_own_port() >= 0 ? "; only this player's drawn" : "");
        }
        if (from == fv->shared_caller)
            g_fp_shared_camera = vp;
        else if ((from == fv->split[0] || from == fv->split[1]) && vp == g_fp_shared_camera)
            g_fp_shared_camera = 0;
        if ((from == fv->split[0] || from == fv->split[1]) && x1 - x0 >= 2 && y1 - y0 >= 2) {
            FP_M32(g_esp + 8) = 0;
            FP_M32(g_esp + 12) = 0;
            FP_M32(g_esp + 16) = FP_M32(fv->screen_w) - 1u;   /* as the one-player layout */
            FP_M32(g_esp + 20) = FP_M32(fv->screen_h) - 1u;
        }
        if (from == fv->pass_caller && g_fp_passes < 2) {
            uint32_t p = FP_M32(fv->state_ptr), id, port = 4u;

            if (p >= 0x10000u && p < 0x84000000u) {
                id = FP_M32(p);
                port = FP_M32(fv->port_direct) ? id
                       : (id < 16u ? FP_M32(fv->port_map + 4u * id) : 4u);
            }
            g_fp_pass[g_fp_passes].port = port;
            g_fp_pass[g_fp_passes].camera_vp = FP_M32(fv->current_vp);
            g_fp_pass[g_fp_passes].hud_vp = vp;
            g_fp_passes++;
        }
    }
    /* A player's pass laid out as part of the screen: a split screen, which
     * keeps the scissors (fp_scissors_frame). As laid out, after the
     * whole-screen layout above. */
    if (from == fv->pass_caller) {
        uint32_t w = FP_M32(fv->screen_w), h = FP_M32(fv->screen_h);

        if (w >= 2u && h >= 2u &&
            ((int)FP_M32(g_esp + 8) > 0 || (int)FP_M32(g_esp + 12) > 0 ||
             (int)FP_M32(g_esp + 16) < (int)w - 1 || (int)FP_M32(g_esp + 20) < (int)h - 1))
            g_fp_frame_partial = 1;
    }
    gen();
}

/*
 * The number keys (as TimeSplitters 2's ts2_weapon_keys): 1 to 9 take the
 * player's first, second, ... weapon, in the order the d-pad steps through
 * them. Future Perfect keeps a player's weapon as a slot (weapons +0x94)
 * in its slot table, and several slots are one weapon -- the pistol, its
 * other mode and a pair are three slots of one category (+0x38) -- so a key
 * counts categories, as the d-pad does: the d-pad's next weapon (USA
 * sub_001BAAF0) walks the weapon order for the first slot of another
 * category that the category picks (sub_001BAA70: the one last held in it,
 * if it still can be) and the player can hold now (sub_001BA410(weapons,
 * slot, 1): has it, has ammo, the mode allows it). This asks the same two
 * of the game, so a key lands on the slot the d-pad would, and a weapon the
 * player has not got, or that is out of ammo, is not counted. The key of
 * the weapon already held does nothing.
 *
 * It runs where the d-pad is read (weapon_change, sub_001BF140, each frame
 * the player may change weapon), before it, and changes the weapon as the
 * d-pad's next weapon does: the change's sound, select (sub_001BA130, which
 * also keeps the slot as the category's last held), the HUD's weapon panel.
 * The key is the controller's for the frame, as recompose latches it
 * (recomp_input_number_key), so online every machine changes alike. A key
 * pressed while no player can change weapon (a menu, a cutscene) is let go
 * at the next frame, not kept for the next match.
 */
extern int recomp_input_number_key(unsigned port);

typedef struct FpWeaponKeys {
    uint32_t look_ptr;            /* the look state being updated, a pointer */
    uint32_t char_off, weapons_off; /* look state -> character -> weapons */
    uint32_t port_map, port_direct; /* as FpLook's */
    uint32_t humans;              /* the number of human players */
    uint32_t order, order_count;  /* the weapon order: slots, as the d-pad steps */
    uint32_t humans_from;         /* the first entry a human's next weapon takes */
    uint32_t table, stride, category_off; /* the slots */
    uint32_t slot_off;            /* weapons: the slot held */
    uint32_t player_off;          /* weapons: the player's number */
    void (*pick)(void);           /* (weapons, slot): its category gives it */
    void (*usable)(void);         /* (weapons, slot, 1): can be held now */
    void (*select)(void);         /* (weapons, slot) */
    void (*cue)(void);            /* (0x3E, player, 1.0f): the change's sound */
    void (*shown)(void);          /* (): the HUD's weapon panel */
} FpWeaponKeys;

static volatile int g_fp_weapon_keys_ran;   /* weapon_change ran this frame */

/* Call a lifted cdecl function: the arguments, then a return address for
 * its ret to pop (none), as the lifted call sites push them. */
static uint32_t fp_call(void (*fn)(void), int n, const uint32_t *arg)
{
    int i;

    for (i = n - 1; i >= 0; i--) {
        g_esp -= 4;
        FP_M32(g_esp) = arg[i];
    }
    g_esp -= 4;
    FP_M32(g_esp) = 0;
    fn();
    g_esp += 4u * (uint32_t)n;            /* the callee popped the return */
    return g_eax;
}

static void fp_weapon_key(const FpWeaponKeys *k, uint32_t weapons, uint32_t player, int n)
{
    uint32_t held = FP_M32(weapons + k->slot_off), held_cat, i, count = 0;
    uint8_t seen[256];

    if (held >= 256u)
        return;
    held_cat = FP_M32(k->table + held * k->stride + k->category_off);
    memset(seen, 0, sizeof seen);
    for (i = k->humans_from; i < k->order_count; i++) {
        uint32_t slot = FP_M32(k->order + 4u * i), cat, a[3];

        if (slot >= 256u)
            continue;
        cat = FP_M32(k->table + slot * k->stride + k->category_off);
        if (cat >= 256u || seen[cat])
            continue;
        if (cat == held_cat) {
            seen[cat] = 1;
            if (++count == (uint32_t)n)
                return;                   /* already held */
            continue;
        }
        a[0] = weapons;
        a[1] = slot;
        a[2] = 1u;
        if (!fp_call(k->pick, 2, a) || !fp_call(k->usable, 3, a))
            continue;
        seen[cat] = 1;
        if (++count == (uint32_t)n) {
            uint32_t cue[3] = { 0x3Eu, player, 0x3F800000u };   /* 1.0f */

            fp_call(k->cue, 3, cue);
            fp_call(k->select, 2, a);
            fp_call(k->shown, 0, NULL);
            return;
        }
    }
}

static void fp_weapon_change(void (*gen)(void), const FpWeaponKeys *k)
{
    uint32_t look = FP_M32(k->look_ptr), chr, weapons, id, port, player;
    int n;

    g_fp_weapon_keys_ran = 1;
    if (look >= 0x10000u && look < 0x84000000u && !(look & 3u)) {
        chr = FP_M32(look + k->char_off);
        weapons = chr >= 0x10000u && chr < 0x84000000u ? FP_M32(chr + k->weapons_off) : 0u;
        id = FP_M32(look);
        port = FP_M32(k->port_direct) ? id : (id < 16u ? FP_M32(k->port_map + 4u * id) : 4u);
        if (weapons >= 0x10000u && weapons < 0x84000000u && port < 4u &&
            (player = FP_M32(weapons + k->player_off)) < FP_M32(k->humans) &&
            (n = recomp_input_number_key(port)) > 0)
            fp_weapon_key(k, weapons, player, n);
    }
    gen();
}

/* Once a frame (fp_frame_clock): a number key no player took last frame is
 * let go. Off the keyboard only; online the key is the latched one, given
 * once a tick, and nothing is kept. */
static void fp_weapon_keys_frame(void)
{
    if (!recomp_lockstep_active() && !g_fp_weapon_keys_ran)
        (void)recomp_input_number_key(0);
    g_fp_weapon_keys_ran = 0;
}

/* -- TimeSplitters: Future Perfect: where this release's functions are ---- */

/*
 * Everything above the co-op hooks is Recompose's template
 * (templates/new-game), the runtime glue every title has. Future Perfect's
 * hooks go between, the same in every release; where they attach is in
 * fp/config/<region>/overrides.inc, as TimeSplitters 2 does it
 * (src/recomp_manual.c). The
 * lifter reads this file as text and does not follow the #include, so
 * fp/scripts/build.py hands it this file and the release's overrides.inc as
 * one. Which release fp/src/recomp/gen was lifted from is in
 * fp/src/recomp/fp_region.h, which fp/scripts/build.py writes with the lift.
 */
#include "fp_region.h"

#if defined(FP_REGION_US)
#include "../config/us/overrides.inc"
#else
#error "fp/src/recomp/fp_region.h names no release this file knows; lift with fp/scripts/build.py"
#endif
