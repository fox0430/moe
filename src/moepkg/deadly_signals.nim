#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

## Signals that end the editor, and the mask that keeps them for the watcher.
##
## The set is blocked in every thread so each signal stays pending until
## `signal_watcher` takes it: a real handler cannot allocate or write files as
## an emergency save must. It is blocked only by starting the watcher (blocked
## with no reader, moe could not be killed), before any other thread exists.
## Signals inherited as ignored are left out, so `nohup moe` survives its
## terminal closing.

import std/posix

type
  KeyboardActions* = object ## What `absorbKeyboardSignals` replaced.
    saved: array[2, Sigaction]
    replaced: array[2, bool]

  TerminalJob* = enum
    tjNone ## stdin is not moe's controlling terminal, as under `setsid`.
    tjForeground ## moe holds its terminal.
    tjBackground ## Another job holds it; touching it would stop moe.

let
  # Not `const`: the posix signal numbers are `importc` variables on
  # macOS and Windows.
  DeadlySignals* = [SIGHUP, SIGINT, SIGQUIT, SIGTERM]
    ## SIGINT and SIGQUIT come only from `kill` while the terminal is raw.

  KeyboardSignals = [SIGINT, SIGQUIT]
    ## What a cooked-mode terminal sends on Ctrl-C and Ctrl-\.

var
  blockedBefore: Sigset
  haveBlockedBefore: bool
  blockDepth: int
    ## How many `blockDeadlySignals` calls still owe a
    ## `restoreDeadlySignalDefaults`. Only the outermost pair touches the
    ## `haveBlockedBefore` baseline, so nested blocks cannot shift it.

proc sigactionQuery(
  sig: cint, act: ptr Sigaction, old: var Sigaction
): cint {.importc: "sigaction", header: "<signal.h>".}

proc ignored(sig: cint): bool =
  ## Whether `sig` is set to be ignored, as `nohup` leaves SIGHUP.
  var current: Sigaction
  sigactionQuery(sig, nil, current) == 0 and current.sa_handler == SIG_IGN

proc deadlySet*(mask: var Sigset): bool =
  ## Fill `mask` with the `DeadlySignals` that are not ignored.
  if sigemptyset(mask) != 0:
    return false
  for sig in DeadlySignals:
    if not ignored(sig) and sigaddset(mask, sig) != 0:
      return false
  true

proc setThreadMask(how: cint, mask: Sigset, previous: var Sigset): bool =
  var mask = mask
  sigemptyset(previous) == 0 and pthread_sigmask(how, mask, previous) == 0

proc setThreadMask(how: cint, mask: Sigset): bool =
  var previous: Sigset
  setThreadMask(how, mask, previous)

proc blockSignal*(sig: cint, previous: var Sigset): bool =
  ## Block `sig` for this thread, saving the mask it replaced.
  var mask: Sigset
  sigemptyset(mask) == 0 and sigaddset(mask, sig) == 0 and
    setThreadMask(SIG_BLOCK, mask, previous)

proc restoreThreadMask*(previous: Sigset) =
  discard setThreadMask(SIG_SETMASK, previous)

template withSignalBlocked*(sig: cint, body: untyped) =
  ## Block `sig` for this thread across `body`.
  block:
    var previous: Sigset
    let blocked = blockSignal(sig, previous)
    try:
      body
    finally:
      if blocked:
        restoreThreadMask(previous)

proc setAction(sig: cint, handler: proc(sig: cint) {.noconv.}): bool =
  var
    act = Sigaction(sa_handler: handler)
    previous: Sigaction
  sigemptyset(act.sa_mask) == 0 and sigaction(sig, act, previous) == 0

proc blockDeadlySignals*(): bool =
  ## Block `DeadlySignals` for this thread, remembering what was blocked
  ## before so `restoreDeadlySignalDefaults` can leave it blocked.
  ## Calls nest: each successful call needs one restore.
  var mask, previous: Sigset
  if not deadlySet(mask):
    return false
  if not setThreadMask(SIG_BLOCK, mask, previous):
    return false
  if blockDepth == 0:
    blockedBefore = previous
    haveBlockedBefore = true
  inc blockDepth
  true

{.push stackTrace: off, profiler: off.}
proc unblockInChild() {.noconv.} =
  ## Runs in a forked child, before anything else: no allocation, no GC.
  ## Uses `sigprocmask`: after `fork` only async-signal-safe calls are allowed.
  var mask, previous: Sigset
  if sigemptyset(mask) != 0:
    return
  for sig in DeadlySignals:
    discard sigaddset(mask, sig)
  discard sigprocmask(SIG_UNBLOCK, mask, previous)

{.pop.}

proc unblockInForkedChildren*(): bool =
  ## Unblock the set in every child `fork` makes from now on (older Nim's
  ## `osproc` forks, and `exec` keeps the mask). `posix_spawn` skips these
  ## handlers, so its callers clear the mask themselves.
  pthread_atfork(nil, nil, unblockInChild) == 0

proc clearSignalMask*(): bool =
  ## Unblock everything for this thread; for a child between `fork` and `exec`.
  var mask: Sigset
  sigemptyset(mask) == 0 and setThreadMask(SIG_SETMASK, mask)

proc signalName*(sig: cint): string =
  ## Short name as `kill -l` prints it.
  # Not a `case`: on some systems the numbers are not known until run time.
  if sig == SIGHUP:
    "HUP"
  elif sig == SIGINT:
    "INT"
  elif sig == SIGQUIT:
    "QUIT"
  elif sig == SIGTERM:
    "TERM"
  else:
    $sig

proc reraiseAsDeath*(sig: cint) =
  ## Re-raise `sig` with its default action, so the parent sees `WIFSIGNALED`
  ## (`quit` clamps at 127) and SIGQUIT still dumps core. Returns only on
  ## failure.
  var mask: Sigset
  if not setAction(sig, SIG_DFL) or sigemptyset(mask) != 0 or sigaddset(mask, sig) != 0:
    return
  if setThreadMask(SIG_UNBLOCK, mask):
    discard kill(getpid(), sig)

proc restoreDeadlySignalDefaults*() =
  ## Restore the default action of the non-ignored `DeadlySignals` and unblock
  ## them, leaving signals blocked before `blockDeadlySignals` blocked.
  ## Used when the watcher cannot take them. An inner restore of nested blocks
  ## only drops the depth; the outermost one restores the baseline.
  var mask: Sigset
  if not deadlySet(mask):
    return
  for sig in DeadlySignals:
    if sigismember(mask, sig) == 1:
      discard setAction(sig, SIG_DFL)
  if blockDepth > 1:
    dec blockDepth
    return
  if haveBlockedBefore:
    var unblock = mask
    for sig in DeadlySignals:
      if sigismember(blockedBefore, sig) == 1:
        discard sigdelset(unblock, sig)
    discard setThreadMask(SIG_UNBLOCK, unblock)
    haveBlockedBefore = false
  else:
    discard setThreadMask(SIG_UNBLOCK, mask)
  blockDepth = 0

proc absorb(sig: cint) {.noconv.} =
  discard

proc absorbKeyboardSignals*(): KeyboardActions =
  ## Catch `KeyboardSignals` with a no-op handler, for when nothing takes them.
  ## Not `SIG_IGN`: a child would inherit it through `exec` and ignore Ctrl-C.
  var act = Sigaction(sa_handler: absorb, sa_flags: SA_RESTART)
  if sigemptyset(act.sa_mask) != 0:
    return
  for i, sig in KeyboardSignals:
    if not ignored(sig):
      result.replaced[i] = sigaction(sig, act, result.saved[i]) == 0

proc restoreKeyboardSignals*(actions: KeyboardActions) =
  for i, sig in KeyboardSignals:
    if actions.replaced[i]:
      var
        act = actions.saved[i]
        replaced: Sigaction
      discard sigaction(sig, act, replaced)

proc stdinHoldsTerminal*(): bool =
  ## Whether stdin is a terminal moe holds: the precondition for moving the
  ## foreground job with `tcsetpgrp(STDIN_FILENO, ...)`. `terminalJob` may
  ## report foreground through stdout or `/dev/tty` while stdin is redirected,
  ## and handing the terminal over then would fail.
  tcgetpgrp(STDIN_FILENO) == getpgrp()

proc terminalJob*(): TerminalJob =
  ## Where moe stands on its terminal. Probes stdin, stdout and stderr in
  ## order: any of them may be redirected while the terminal remains.
  for fd in [cint(STDIN_FILENO), cint(STDOUT_FILENO), cint(STDERR_FILENO)]:
    if isatty(fd) != 1:
      continue
    let holder = tcgetpgrp(fd)
    if holder < 0:
      continue
    if holder == getpgrp():
      return tjForeground
    else:
      return tjBackground
  # All standard streams are redirected, but the process may still have a
  # controlling terminal. Check it directly. Non-blocking: this also runs on
  # the death path, where waiting for a carrier would keep moe alive.
  let tty = posix.open("/dev/tty".cstring, O_RDONLY or O_NONBLOCK or O_NOCTTY)
  if tty < 0:
    return tjNone
  let holder = tcgetpgrp(tty)
  discard posix.close(tty)
  if holder < 0:
    tjNone
  elif holder == getpgrp():
    tjForeground
  else:
    tjBackground
