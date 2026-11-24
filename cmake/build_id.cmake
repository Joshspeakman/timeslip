# Writes OUT, a header naming this build by its sources: this repository's
# commit and the toolkit's, each marked -dirty when it has uncommitted
# changes. An online co-op session refuses a machine whose build differs
# (xboxrecomp src/kernel/recomp_lockstep_net.c), because a different build
# computes a different game. Run at every build (cmake -P), and rewrites OUT
# only when the name changes, so an unchanged build recompiles nothing.
#
#   cmake -DSRC=<repo> -DOUT=<header> -P cmake/build_id.cmake
function(commit_of dir out)
    execute_process(COMMAND git -C "${dir}" rev-parse --short=12 HEAD
        OUTPUT_VARIABLE c OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET RESULT_VARIABLE r)
    if(NOT r EQUAL 0 OR c STREQUAL "")
        set(${out} "unknown" PARENT_SCOPE)
        return()
    endif()
    # Submodules' own state is not this repository's: the toolkit's commit
    # is named on its own, and its third_party checkouts do not change it.
    execute_process(COMMAND git -C "${dir}" diff --quiet --ignore-submodules HEAD
        RESULT_VARIABLE dirty ERROR_QUIET)
    if(NOT dirty EQUAL 0)
        set(c "${c}-dirty")
    endif()
    set(${out} "${c}" PARENT_SCOPE)
endfunction()

commit_of("${SRC}" ts2)
commit_of("${SRC}/xboxrecomp" xbr)
set(text "/* Written at every build by cmake/build_id.cmake. */\n#define TS2_BUILD_ID \"ts2 ${ts2} xbr ${xbr}\"\n")
if(EXISTS "${OUT}")
    file(READ "${OUT}" old)
else()
    set(old "")
endif()
if(NOT old STREQUAL text)
    file(WRITE "${OUT}" "${text}")
endif()
