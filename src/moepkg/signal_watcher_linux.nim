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

## A thread that takes the deadly signals for the event loop, and ends the
## process itself when the loop does not answer in time.
##
## One clock starts at the first signal: the loop has `answerDeadline` to start
## preserving and `finishDeadline` to finish, after which the watcher re-raises
## the signal, so a stuck loop never makes moe unkillable. Later signals do not
## shorten it: closing a terminal sends several.
##
## While a shell command has the terminal, signals are passed on to it, then
## SIGHUP and SIGKILL, so the loop gets back in time. Ctrl-C and Ctrl-\ typed
## there are dropped; the same signals from `kill` are answered.
##
## Signals are process-wide, so there is one watcher per process.

import std/[atomics, os, posix, termios]

import pkg/[chronos, results]
import pkg/chronos/threadsync

import deadly_signals, logger

type Stage = enum
  sStarting ## The loop is not running yet; any signal ends the process.
  sOpen ## The loop answers; nothing is being preserved.
  sFinishing ## The loop is saving buffers, or tearing down after a quit.
  sSettled ## The buffers are dealt with; any signal ends the process at once.
  sExpired ## The watcher is ending the process.

var
  running: Atomic[bool] ## Written once by `startSignalWatcher`, before the loop runs.
  original: Termios ## The terminal as moe found it.
  hasOriginal: bool
  stage: Atomic[int]
  taken: Atomic[int] ## The first signal that arrived, or 0.
  handedOver: Atomic[bool] ## The TUI is handed over; keyboard signals drop.
  handedBackAt: Atomic[int64]
    ## When the TUI was last taken back, in nanoseconds. See `KeyGrace`.
  commandTarget: Atomic[int]
    ## A pid, or a negative process group, to pass signals on to; 0 for none.
  wake: ThreadSignalPtr
  answerDeadline, finishDeadline: Duration
  watcher: Thread[Sigset]

proc currentStage(): Stage =
  Stage(stage.load)

proc moveFrom(expected: Stage, next: Stage): bool =
  var e = ord(expected)
  stage.compareExchange(e, ord(next))

const TerminalReset =
  "\x18" & # Abort an escape sequence a frame write left open.
  "\e[?2026l" & # Synchronized output, which a frame write may have left on.
  "\e[?9l\e[?1000l\e[?1002l\e[?1003l\e[?1006l" & # Mouse reporting.
  "\e[?1004l" & # Focus reporting.
  "\e[?2004l" & # Bracketed paste.
  "\e[0 q\e[?25h" & # Cursor style and visibility.
  "\e[?1049l" # Alternate screen, last: it restores the cursor position.

const
  Slice = 100.milliseconds ## How often a command being ended is looked at.
  StopGap = 400.milliseconds ## Past `Slice`, a wait this long means a stop.
  KeyGrace = 200.milliseconds
    ## A key signal this soon after the TUI is taken back was typed before.

var SI_KERNEL {.importc, header: "<signal.h>".}: cint

proc restoreTerminal() =
  ## Put the terminal back as moe found it, only while the TUI has it and moe is
  ## in the foreground. Never blocks, so a stalled terminal cannot keep moe alive.
  # sExpired only follows sOpen: the watcher gave up on a loop that had it.
  if not hasOriginal or currentStage() in {sStarting, sSettled} or handedOver.load or
      terminalJob() == tjBackground:
    return
  discard tcSetAttr(STDIN_FILENO, TCSANOW, original.addr)
  let tty = posix.open("/dev/tty", O_WRONLY or O_NONBLOCK or O_NOCTTY)
  if tty >= 0:
    discard write(tty, TerminalReset.cstring, TerminalReset.len)
    discard close(tty)

proc die(sig: cint) {.noreturn.} =
  restoreTerminal()
  reraiseAsDeath(sig)
  exitnow(128 + sig)

proc nextSignalWithin(mask: var Sigset, timeout: Duration, info: var SigInfo): cint =
  ## The next signal in `mask`, or 0 once `timeout` passes.
  let ns = max(timeout.nanoseconds, 0)
  var ts = Timespec(
    tv_sec: posix.Time(ns div 1_000_000_000), tv_nsec: int(ns mod 1_000_000_000)
  )
  max(sigtimedwait(mask, info, ts), 0)

proc keyAtHandedOverTerminal(sig: cint, info: SigInfo): bool =
  ## Ctrl-C or Ctrl-\ typed while the TUI is handed over (sent by the kernel,
  ## unlike `kill`).
  sig in [SIGINT, SIGQUIT] and info.si_code == SI_KERNEL and (
    handedOver.load or
    Moment.now().epochNanoSeconds - handedBackAt.load < KeyGrace.nanoseconds
  )

proc passOn(sig: cint) =
  ## Hand `sig` to the command the TUI is handed over to, if one runs.
  let target = commandTarget.load
  if target != 0:
    discard kill(Pid(target), sig)

proc watch(mask: Sigset) {.thread.} =
  var
    mask = mask
    info: SigInfo
    first: cint
  while first <= 0:
    first = sigwaitinfo(mask, info)
    if first > 0 and keyAtHandedOverTerminal(first, info):
      first = 0
  # Before reading the stage and target: `withCommandInTerminal` writes its
  # target before reading `taken`, so one side always sees the other.
  taken.store(first.int)
  if currentStage() in {sStarting, sSettled}:
    die(first)
  passOn(first)
  discard wake.fireSync()

  var
    since = Moment.now()
    lastWake = since
    chased = 0 ## The command being ended, as `commandTarget` names it.
    chasedSince = since
    escalated = 0 ## Signals sent past the first: SIGHUP, then SIGKILL.
  while true:
    let now = Moment.now()
    # A gap far past `Slice` means moe was stopped (Ctrl-Z, SIGTTOU); the clock
    # counts only running time.
    let stoppedFor = now - lastWake - Slice
    if stoppedFor > StopGap:
      since += stoppedFor
      chasedSince += stoppedFor
    lastWake = now
    let target = commandTarget.load
    if target != chased:
      (chased, chasedSince, escalated) = (target, now, 0)
    elif target != 0:
      # SIGHUP at a third of the answer deadline (interactive shells ignore
      # SIGTERM), SIGKILL at two thirds.
      let
        hangUpAfter = nanoseconds(answerDeadline.nanoseconds div 3)
        killAfter = nanoseconds(answerDeadline.nanoseconds * 2 div 3)
      if escalated == 0 and now - chasedSince >= hangUpAfter:
        discard kill(Pid(target), SIGHUP)
        escalated = 1
      elif escalated == 1 and now - chasedSince >= killAfter:
        discard kill(Pid(target), SIGKILL)
        escalated = 2

    # Only the answer is short: cutting a save off loses what it is for.
    let
      answering = currentStage() == sOpen
      left = since + (if answering: answerDeadline else: finishDeadline) - now
    if left > ZeroDuration:
      let sig = nextSignalWithin(mask, min(left, Slice), info)
      if sig > 0 and not keyAtHandedOverTerminal(sig, info):
        if currentStage() == sSettled:
          die(first)
        passOn(sig)
    elif not answering or moveFrom(sOpen, sExpired):
      die(first)
    # Otherwise the loop began saving just now, and gets the longer clock.

proc startSignalWatcher*(answer = 10.seconds, finish = 20.seconds): bool =
  ## Block the set and start the watcher. Call before any other thread exists.
  ## False on failure, leaving the default actions. `answer` and `finish` are
  ## the deadlines counted from the first signal.
  var mask: Sigset
  if not deadlySet(mask):
    return false
  var hasSignal = false
  for sig in DeadlySignals:
    if sigismember(mask, sig) == 1:
      hasSignal = true
      break
  if not hasSignal:
    # Every deadly signal is ignored; there is nothing to watch.
    return false
  let w = ThreadSignalPtr.new()
  if w.isErr:
    return false
  wake = w.get
  answerDeadline = answer
  finishDeadline = finish
  stage.store(ord(sStarting))
  taken.store(0)
  hasOriginal = tcGetAttr(STDIN_FILENO, original.addr) == 0

  if not blockDeadlySignals():
    discard wake.close()
    return false
  if not unblockInForkedChildren():
    # Children would inherit the set blocked: better not to watch.
    restoreDeadlySignalDefaults()
    discard wake.close()
    return false
  try:
    createThread(watcher, watch, mask)
  except ResourceExhaustedError:
    restoreDeadlySignalDefaults()
    discard wake.close()
    return false
  running.store(true)
  true

proc signalWatcherRunning*(): bool =
  running.load

proc loopAnswers*() =
  ## The event loop runs: from now on a signal is handed to it.
  discard moveFrom(sStarting, sOpen)

proc signalForwarded*(): Future[void] {.async: (raises: [CancelledError]).} =
  ## Completes when the first signal arrives; `takenSignal` names it.
  try:
    await wake.wait()
  except AsyncError as ex:
    # Without the wake-up, look for the signal instead.
    logError("signal_watcher", "Cannot wait for deadly signals: " & ex.msg)
    while taken.load == 0:
      await sleepAsync(50.milliseconds)

proc takenSignal*(): cint =
  ## The first signal that arrived, or 0.
  taken.load.cint

proc waitForTakenSignal*(timeout: Duration): cint =
  ## The signal taken so far, waiting up to `timeout` for one. Blocks.
  let until = Moment.now() + timeout
  result = takenSignal()
  while result == 0 and Moment.now() < until:
    sleep(10)
    result = takenSignal()

proc beginPreserving*(): bool =
  ## Start saving, extending the clock to `finishDeadline`. False if already
  ## saving or expired; true without a watcher, so a crash still preserves.
  moveFrom(sOpen, sFinishing) or moveFrom(sStarting, sFinishing)

proc beginWindingDown*() =
  ## A signal arrived after the user quit: give teardown `finishDeadline` too.
  discard moveFrom(sOpen, sFinishing)

proc settle*() =
  ## The buffers are dealt with; the next signal ends the process at once.
  ## The finish deadline from the first signal still caps teardown.
  discard moveFrom(sOpen, sSettled) or moveFrom(sFinishing, sSettled)

template withTerminalHandedOver*(body: untyped) =
  ## Drop Ctrl-C and Ctrl-\ while a shell command has the terminal, including
  ## the switch to cooked mode and back. Not reentrant; callers must not nest.
  handedOver.store(true)
  let absorbed = absorbKeyboardSignals()
  try:
    body
  finally:
    restoreKeyboardSignals(absorbed)
    handedBackAt.store(Moment.now().epochNanoSeconds)
    handedOver.store(false)

template withCommandInTerminal*(target: int, body: untyped) =
  ## Pass signals on to `target` (a pid, or a negative process group) across
  ## `body`, which must not reap it: its pid could be reused. Not reentrant;
  ## callers must not nest.
  commandTarget.store(target)
  try:
    # One that arrived before the command was known was not passed on.
    let early = takenSignal()
    if early != 0:
      discard kill(Pid(target), early)
    body
  finally:
    commandTarget.store(0)
