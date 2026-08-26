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

## System clipboard integration using external tools
##
## This module provides clipboard read/write functionality using external
## clipboard tools like xclip, xsel, wl-clipboard, etc.

import std/[monotimes, options, os, osproc, streams, strutils, times]

# POSIX-only: process groups, non-blocking fds, `waitid`. Gate is in moe.nim.
import std/posix

import pkg/results

import config, encoding, logger

type
  ClipboardOperation* {.pure.} = enum
    ## `pure` avoids name collisions with std/posix and streams.
    read
    write

  ClipboardError* = object of CatchableError ## Error type for clipboard operations

const
  WriteTimeoutMs = 10_000 ## Timeout for clipboard writes (wl-copy: briefly polled).
  ReadTimeoutMs = 2_000 ## Idle timeout between reads; INCR transfers continue.
  MaxTotalReadMs = 10_000 ## Total read timeout; partial data discarded.
  MaxReadSize = 16 * 1024 * 1024 ## Max clipboard output size.
  MaxStderrCapture = 4 * 1024 ## Max stderr bytes kept for errors.
  MaxDiagnosticBytes = 200 ## Max diagnostic bytes shown in status line.
  MaxStderrDrainPerCall = 64 * 1024 ## Max stderr bytes drained per call.
  DrainReadBufSize = 4096 ## Reused per-read buffer for the stderr drain.
  DrainGraceMs = 200 ## Grace for post-deadline drain.
  ReapTimeoutMs = 200 ## Timeout to reap killed child.
  ExitGraceMs = 200 ## Grace for tool to exit after input.
  ExitUnknown = int.low ## Sentinel for unknown exit code.
  ExitStatusLost = -3 ## Tool gone but exit status lost.
  ClipboardProcessOptions = {poUsePath, poDaemon}
    ## poDaemon: new process group for cleanup.

var
  P_PID {.importc, header: "<sys/wait.h>".}: cint
  CLD_EXITED {.importc, header: "<signal.h>".}: cint

proc decodeSiginfo(info: SigInfo): int =
  ## Decode a `waitid` result to an exit code.
  if info.si_code == CLD_EXITED:
    return info.si_status.int
  return 128 + info.si_status.int

proc pidStillExists(p: Process): bool =
  ## Null-signal probe. False only when the PID is provably gone.
  if kill(Pid(p.processID), 0) == 0:
    return true
  return osLastError().cint != ESRCH

proc processGone(p: Process, exitCode: var int): bool =
  ## True if process gone or PID recycled; sets exitCode if available.
  # Prefer peekExitCode to keep Process state consistent.
  try:
    let c = p.peekExitCode()
    if c != -1:
      exitCode = c
      return true
  except CatchableError:
    discard
  # WNOWAIT checks without reaping; otherwise Process state is lost.
  # ECHILD = already reaped elsewhere, avoid signaling recycled PID.
  var info: SigInfo
  info.si_pid = Pid(0)
  let wr = waitid(P_PID, Id(p.processID), info, WEXITED or WNOHANG or WNOWAIT)
  if wr == -1:
    if osLastError().cint == ECHILD:
      return true
    return not pidStillExists(p)
  if info.si_pid == Pid(0):
    return false
  # Exited but unreaped; reap via stdlib, keep waitid status on race.
  try:
    let c = p.peekExitCode()
    if c != -1:
      exitCode = c
      return true
  except CatchableError:
    discard
  exitCode = decodeSiginfo(info)
  return true

proc processGone(p: Process): bool =
  var ignored = ExitUnknown
  processGone(p, ignored)

proc killProcessGroupOf(p: Process) =
  ## SIGKILL whole process group; handles forking tools (wl-copy etc.).
  let pid = Pid(p.processID)
  if pid.int <= 0:
    return
  if getpgid(pid) == pid:
    discard kill(Pid(-pid.int), SIGKILL)

proc killIfAlive(p: Process, exitCode: var int): bool {.discardable.} =
  ## Kill p if alive; true if already gone (exitCode set when available).
  if processGone(p, exitCode):
    return true
  killProcessGroupOf(p)
  try:
    p.kill()
  except CatchableError:
    discard
  return false

proc killIfAlive(p: Process) =
  var ignored = ExitUnknown
  killIfAlive(p, ignored)

proc pollExitUntil(p: Process, deadline: MonoTime): int =
  ## Poll exit until deadline; -1 running, -2 error, ExitStatusLost if reaped elsewhere.
  while true:
    try:
      let code = p.peekExitCode()
      if code != -1:
        return code
    except CatchableError:
      killIfAlive(p)
      return -2
    var decoded = ExitUnknown
    if processGone(p, decoded):
      if decoded != ExitUnknown:
        return decoded
      return ExitStatusLost
    if getMonoTime() >= deadline:
      return -1
    sleep(1)

proc cleanupClipboardProcess(p: Process): bool {.discardable.} =
  ## Kill and reap p within ReapTimeoutMs; leaves handles open (caller closes).
  if p.isNil:
    return true
  var exitCode = ExitUnknown
  if killIfAlive(p, exitCode):
    return true
  let reapCode =
    pollExitUntil(p, getMonoTime() + initDuration(milliseconds = ReapTimeoutMs))
  if reapCode >= 0 or reapCode == ExitStatusLost:
    return true
  if processGone(p):
    return true
  if reapCode == -2:
    logWarn(
      "clipboard",
      "child process status query failed during reap; may remain until editor exits (pid=" &
        $p.processID & ")",
    )
    return false
  logWarn(
    "clipboard",
    "child process remains after ReapTimeoutMs; leaving zombie until editor exits (pid=" &
      $p.processID & ")",
  )
  return false

type ToolDiagnostics = object
  ## Bounded stderr capture. `head` feeds `exitCodeDetail`, `tail` decides
  ## empty-selection. Every drained byte reaches `tail`.
  head: string
  tail: string
  readBuf: string ## Reused drain buffer.

proc add(d: var ToolDiagnostics, s: string) =
  if d.head.len < MaxStderrCapture:
    d.head.add(s[0 ..< min(s.len, MaxStderrCapture - d.head.len)])
  d.tail.add(s)
  if d.tail.len > 2 * MaxStderrCapture:
    d.tail = d.tail[d.tail.len - MaxStderrCapture .. ^1]

proc makeNonBlocking(fd: cint): bool =
  let fl = fcntl(fd, F_GETFL)
  if fl == -1:
    return false
  return fcntl(fd, F_SETFL, fl or O_NONBLOCK) != -1

proc diagnosticsFd(p: Process): cint =
  ## Non-blocking stderr fd, or -1 if merged/unusable.
  if p.isNil:
    return -1
  let outFd = p.outputHandle().cint
  let errFd = p.errorHandle().cint
  if errFd >= 0 and errFd != outFd and makeNonBlocking(errFd): errFd else: -1.cint

proc drainDiagnostics(fd: cint, dst: var ToolDiagnostics) =
  ## Non-blocking stderr drain.
  if fd < 0:
    return
  if dst.readBuf.len == 0:
    dst.readBuf = newString(DrainReadBufSize)
  var drained = 0
  while drained < MaxStderrDrainPerCall:
    let r = read(
      fd, addr dst.readBuf[0], min(dst.readBuf.len, MaxStderrDrainPerCall - drained)
    )
    if r > 0:
      drained += r
      dst.add(dst.readBuf[0 ..< r])
      continue
    if r == 0:
      return
    if osLastError().cint == EINTR:
      continue
    return

proc pollExitDraining(
    p: Process, deadline: MonoTime, errFd: cint, diag: var ToolDiagnostics
): int =
  ## Poll exit while draining stderr.
  while true:
    drainDiagnostics(errFd, diag)
    var slice = getMonoTime() + initDuration(milliseconds = 5)
    if slice > deadline:
      slice = deadline
    let code = pollExitUntil(p, slice)
    if code != -1:
      return code
    if getMonoTime() >= deadline:
      return -1

const EmptySelectionMarkers = [
  "target string not available", # xclip
  "target utf8_string not available", # xclip
  "nothing is copied", # wl-paste
  "no selection", # xsel, wl-paste
]

proc lastLine(s: string): string =
  ## Last non-empty line.
  for line in s.splitLines:
    let stripped = line.strip()
    if stripped.len > 0:
      result = stripped

proc firstLine(s: string): string =
  ## First non-empty line.
  for line in s.splitLines:
    let stripped = line.strip()
    if stripped.len > 0:
      return stripped
  return ""

proc sanitizeDiagnosticLine(s: string): string =
  ## Sanitize tool message for display: strip controls, bound length, fix UTF-8.
  var stripped = newStringOfCap(s.len)
  for c in s:
    let o = c.ord
    if o < 0x20 or o == 0x7F:
      if stripped.len > 0 and stripped[^1] != ' ':
        stripped.add(' ')
    else:
      stripped.add(c)
  stripped = stripped.strip()
  if stripped.len > MaxDiagnosticBytes:
    stripped = stripped[0 ..< MaxDiagnosticBytes] & "..."
  return sanitizeInvalidUtf8(stripped)

proc looksLikeEmptySelection(s: string): bool =
  let lowered = s.toLowerAscii
  for marker in EmptySelectionMarkers:
    if lowered.contains(marker):
      return true
  return false

proc finalDiagnostic(d: ToolDiagnostics): string =
  ## Last tool message.
  lastLine(d.tail)

proc looksLikeEmptySelection(d: ToolDiagnostics): bool =
  ## Only final message decides; marker + failure = failure.
  d.finalDiagnostic.looksLikeEmptySelection

proc exitCodeDetail(exitCode: int, d: ToolDiagnostics): string =
  ## "code N" plus first diagnostic line if present.
  let detail = sanitizeDiagnosticLine(firstLine(d.head))
  if detail.len > 0:
    "code " & $exitCode & ": " & detail
  else:
    "code " & $exitCode

proc exitCodeErr(exitCode: int, toolStderr: ToolDiagnostics): Result[string, string] =
  ## Error for non-zero exit.
  Result[string, string].err(
    "The clipboard tool exited with " & exitCodeDetail(exitCode, toolStderr)
  )

proc emptySelection(
    exitCode: int, toolStderr: ToolDiagnostics
): Result[string, string] =
  ## Distinguish empty selection from real failure via diagnostics.
  if looksLikeEmptySelection(toolStderr):
    logWarn(
      "clipboard",
      "tool reported an empty selection (exit code " & $exitCode & "): " &
        sanitizeDiagnosticLine(toolStderr.finalDiagnostic),
    )
    return Result[string, string].ok("")
  return exitCodeErr(exitCode, toolStderr)

proc outputTooLargeErr(p: Process, maxReadSize: int): Result[string, string] =
  ## Kill tool and report oversized output.
  cleanupClipboardProcess(p)
  Result[string, string].err(
    "The clipboard tool output exceeded the " & $maxReadSize & " byte limit"
  )

proc timedOutErr(
    p: Process,
    boundMs: int,
    hitTotalBound = false,
    note = "timed out waiting for clipboard tool with empty output",
    detail = "",
): Result[string, string] =
  ## Kill tool and report timeout.
  cleanupClipboardProcess(p)
  logWarn("clipboard", note)
  if hitTotalBound:
    let suffix =
      if detail.len > 0:
        "; " & detail
      else:
        ""
    return Result[string, string].err(
      "The clipboard tool did not finish within " & $boundMs & " ms" & suffix
    )
  if detail.len > 0:
    return Result[string, string].err("Timed out after " & $boundMs & " ms; " & detail)
  return Result[string, string].err(
    "Timed out after " & $boundMs & " ms with no output from the clipboard tool"
  )

proc noDataOutcome(
    process: Process,
    toolStderr: var ToolDiagnostics,
    errFd: cint,
    boundMs: int,
    hitTotalBound: bool,
    graceMs: int,
): Result[string, string] =
  ## No output before deadline; check exit code/diagnostics to tell empty selection from timeout.
  let code = pollExitDraining(
    process, getMonoTime() + initDuration(milliseconds = graceMs), errFd, toolStderr
  )
  if code >= 0:
    cleanupClipboardProcess(process)
    if code == 0:
      return Result[string, string].ok("")
    return emptySelection(code, toolStderr)
  if looksLikeEmptySelection(toolStderr):
    cleanupClipboardProcess(process)
    logWarn(
      "clipboard",
      "tool reported an empty selection before exiting: " &
        sanitizeDiagnosticLine(toolStderr.finalDiagnostic),
    )
    return Result[string, string].ok("")
  return timedOutErr(process, boundMs, hitTotalBound)

proc dataDespiteDeadline(
    process: Process,
    output: string,
    note: string,
    toolStderr = ToolDiagnostics(),
    knownExitCode = ExitUnknown,
    hardDeadline = MonoTime(),
    acceptRunning = false,
): Result[string, string] =
  ## Return buffered output despite deadline after verifying exit code.
  let now = getMonoTime()
  let waitUntil =
    if hardDeadline == MonoTime():
      now + initDuration(milliseconds = ExitGraceMs)
    elif hardDeadline > now:
      let capped = now + initDuration(milliseconds = ExitGraceMs)
      if capped > hardDeadline: hardDeadline else: capped
    else:
      now
  var mutableStderr = toolStderr
  let code =
    if knownExitCode != ExitUnknown:
      knownExitCode
    elif process.isNil:
      -1
    else:
      pollExitDraining(process, waitUntil, process.diagnosticsFd(), mutableStderr)
  cleanupClipboardProcess(process)
  if code > 0:
    return exitCodeErr(code, mutableStderr)
  if code == ExitStatusLost:
    logWarn("clipboard", note & " (" & $output.len & " bytes; exit status lost)")
    return Result[string, string].ok(sanitizeInvalidUtf8(output))
  if code == -1 and acceptRunning:
    logWarn(
      "clipboard", note & " (" & $output.len & " bytes; tool killed while running)"
    )
    return Result[string, string].ok(sanitizeInvalidUtf8(output))
  if code == -2 or code == -1:
    return Result[string, string].err("Failed to wait for the clipboard tool")
  logWarn("clipboard", note & " (" & $output.len & " bytes)")
  return Result[string, string].ok(sanitizeInvalidUtf8(output))

proc waitForExitBounded(
    p: Process, deadline: MonoTime, errFd: cint, diag: var ToolDiagnostics
): int =
  ## Bounded wait draining stderr to avoid blocking on full pipe.
  if p.isNil:
    return -2
  result = pollExitDraining(p, deadline, errFd, diag)
  if result == -1:
    cleanupClipboardProcess(p)

proc writeFailed(msg: string): Result[void, string] =
  Result[void, string].err(msg)

proc toolGoneWrite(
    p: Process, fallbackMsg: string, errFd: cint, diag: var ToolDiagnostics
): Result[void, string] =
  ## Report write failure from exited tool, preferring exit code.
  let exitCode = pollExitDraining(
    p, getMonoTime() + initDuration(milliseconds = ExitGraceMs), errFd, diag
  )
  cleanupClipboardProcess(p)
  if exitCode > 0:
    return writeFailed("exit " & exitCodeDetail(exitCode, diag))
  if exitCode == 0:
    return writeFailed("The clipboard tool closed its input before the write completed")
  writeFailed(fallbackMsg)

proc closeToolInput(p: Process): Result[void, string] =
  ## Close tool stdin to signal EOF.
  try:
    p.inputStream.close()
  except CatchableError as e:
    cleanupClipboardProcess(p)
    return writeFailed("Failed to close the clipboard tool input: " & e.msg)
  return Result[void, string].ok()

proc writeAllBounded(
    p: Process, text: string, deadline: MonoTime, errFd: cint, diag: var ToolDiagnostics
): Result[void, string] =
  ## Bounded non-blocking write to stdin.
  if p.isNil:
    return writeFailed("Failed to write to the clipboard tool: process is nil")
  if text.len == 0:
    return closeToolInput(p)
  let fd = p.inputHandle()
  if fd < 0:
    cleanupClipboardProcess(p)
    return writeFailed("Failed to write to the clipboard tool: invalid file descriptor")
  let fl = fcntl(fd.cint, F_GETFL)
  if fl == -1:
    let fcntlErr = osLastError()
    cleanupClipboardProcess(p)
    return writeFailed("Failed to write to the clipboard tool: " & osErrorMsg(fcntlErr))
  if fcntl(fd.cint, F_SETFL, fl or O_NONBLOCK) == -1:
    let fcntlErr = osLastError()
    cleanupClipboardProcess(p)
    return writeFailed("Failed to write to the clipboard tool: " & osErrorMsg(fcntlErr))
  var offset = 0
  while offset < text.len:
    drainDiagnostics(errFd, diag)
    let remaining = deadline - getMonoTime()
    if remaining <= initDuration(milliseconds = 0):
      cleanupClipboardProcess(p)
      return writeFailed(
        "Timed out sending the text to the clipboard tool; it was killed before " &
          "the whole input was accepted"
      )
    var pfd = TPollfd(fd: fd.cint, events: POLLOUT, revents: 0)
    let pollMs = min(((remaining.inNanoseconds + 999_999) div 1_000_000).int, 100).cint
    let n = poll(addr pfd, Tnfds(1), pollMs)
    if n < 0:
      if osLastError().cint == EINTR:
        continue
      let pollErr = osLastError()
      cleanupClipboardProcess(p)
      return writeFailed("Failed to poll the clipboard tool: " & osErrorMsg(pollErr))
    if n == 0:
      continue
    if (pfd.revents and POLLNVAL) != 0:
      cleanupClipboardProcess(p)
      return writeFailed("Failed to poll the clipboard tool: invalid file descriptor")
    if (pfd.revents and POLLOUT) != 0:
      let r = write(fd.cint, addr text[offset], text.len - offset)
      if r < 0:
        let errCode = osLastError().cint
        if errCode == EINTR or errCode == EAGAIN or errCode == EWOULDBLOCK:
          continue
        if errCode == EPIPE:
          return toolGoneWrite(
            p, "Failed to write to the clipboard tool: Broken pipe", errFd, diag
          )
        let writeErr = osLastError()
        cleanupClipboardProcess(p)
        return
          writeFailed("Failed to write to the clipboard tool: " & osErrorMsg(writeErr))
      if r == 0:
        continue
      offset += r
      continue
    if (pfd.revents and (POLLHUP or POLLERR)) != 0:
      return toolGoneWrite(
        p, "Failed to poll the clipboard tool: error on file descriptor", errFd, diag
      )
    sleep(1)
    continue
  return closeToolInput(p)

proc writeAllBounded(
    p: Process, text: string, deadline: MonoTime
): Result[void, string] =
  ## Overload without caller diagnostics.
  var diag = ToolDiagnostics()
  writeAllBounded(p, text, deadline, p.diagnosticsFd(), diag)

proc readAllWithTimeout(
    process: Process,
    timeoutMs: int,
    maxReadSize: int = MaxReadSize,
    maxTotalMs: int = MaxTotalReadMs,
): Result[string, string] =
  ## Read stdout with idle and total timeouts.
  if process.isNil:
    return Result[string, string].err(
      "Timed out after " & $timeoutMs &
        " ms waiting for the clipboard tool: process is nil"
    )
  let fd = process.outputHandle()
  if fd < 0:
    cleanupClipboardProcess(process)
    return Result[string, string].err(
      "Failed to poll the clipboard tool: invalid file descriptor"
    )
  # Make non-blocking to avoid blocking on empty pipe.
  let fl = fcntl(fd.cint, F_GETFL)
  if fl == -1:
    let fcntlErr = osLastError()
    cleanupClipboardProcess(process)
    return Result[string, string].err(
      "Failed to poll the clipboard tool: " & osErrorMsg(fcntlErr)
    )
  if fcntl(fd.cint, F_SETFL, fl or O_NONBLOCK) == -1:
    let fcntlErr = osLastError()
    cleanupClipboardProcess(process)
    return Result[string, string].err(
      "Failed to poll the clipboard tool: " & osErrorMsg(fcntlErr)
    )
  var toolStderr = ToolDiagnostics()
  let errFd = process.diagnosticsFd()
  var output = ""
  var buf = newString(4096)
  # `timeoutMs` bounds stalls, `hardDeadline` bounds total time.
  var deadline = getMonoTime() + initDuration(milliseconds = timeoutMs)
  let hardDeadline = getMonoTime() + initDuration(milliseconds = maxTotalMs)
  while true:
    drainDiagnostics(errFd, toolStderr)
    let remaining = min(deadline, hardDeadline) - getMonoTime()
    if remaining <= initDuration(milliseconds = 0):
      # Deadline exceeded: drain buffered data to check EOF vs truncated.
      let drainStart = getMonoTime()
      var drainDeadline = drainStart + initDuration(milliseconds = DrainGraceMs)
      if hardDeadline > drainStart and drainDeadline > hardDeadline:
        drainDeadline = hardDeadline
      let hitTotalBound = drainStart >= hardDeadline
      var hitEof = false
      while true:
        let r = read(fd, addr buf[0], buf.len)
        if r == 0:
          hitEof = true
          break
        elif r > 0:
          output.add(buf[0 ..< r])
          if output.len > maxReadSize:
            return outputTooLargeErr(process, maxReadSize)
          if getMonoTime() >= drainDeadline:
            break
          continue
        else:
          let errCode = osLastError().cint
          if errCode == EAGAIN or errCode == EWOULDBLOCK:
            break
          elif errCode == EINTR:
            continue
          else:
            let readErr = osLastError()
            cleanupClipboardProcess(process)
            return Result[string, string].err(
              "Failed to read the clipboard tool output: " & osErrorMsg(readErr)
            )
      drainDiagnostics(errFd, toolStderr)
      let boundMs = if hitTotalBound: maxTotalMs else: timeoutMs
      if hitEof:
        if output.len > 0:
          return dataDespiteDeadline(
            process,
            output,
            "EOF reached but deadline exceeded; returning complete data",
            toolStderr,
            hardDeadline = hardDeadline,
            acceptRunning = true,
          )
        return
          noDataOutcome(process, toolStderr, errFd, boundMs, hitTotalBound, ExitGraceMs)
      else:
        # EAGAIN without EOF: not complete; grandchild may still hold stdout.
        if output.len > 0:
          return timedOutErr(
            process,
            boundMs,
            hitTotalBound,
            "timeout with partial output; discarding truncated data (" & $output.len &
              " bytes)",
            "partial output was discarded (" & $output.len & " bytes)",
          )
        return noDataOutcome(process, toolStderr, errFd, boundMs, hitTotalBound, 0)
    var pfd = TPollfd(fd: fd.cint, events: POLLIN, revents: 0)
    let n = poll(
      addr pfd,
      Tnfds(1),
      min(((remaining.inNanoseconds + 999_999) div 1_000_000).int, 100).cint,
    )
    if n < 0:
      if osLastError().cint == EINTR:
        continue
      let pollErr = osLastError()
      cleanupClipboardProcess(process)
      return Result[string, string].err(
        "Failed to poll the clipboard tool: " & osErrorMsg(pollErr)
      )
    if n == 0:
      continue
    if (pfd.revents and POLLNVAL) != 0:
      cleanupClipboardProcess(process)
      return Result[string, string].err(
        "Failed to poll the clipboard tool: invalid file descriptor"
      )
    if (pfd.revents and POLLIN) != 0:
      let r = read(fd, addr buf[0], buf.len)
      if r < 0:
        let errCode = osLastError().cint
        if errCode == EAGAIN or errCode == EWOULDBLOCK:
          if (pfd.revents and POLLERR) != 0:
            # Level-triggered POLLERR would spin; abort.
            cleanupClipboardProcess(process)
            return Result[string, string].err(
              "Failed to poll the clipboard tool: error on file descriptor"
            )
          continue
        if errCode == EINTR:
          continue
        let readErr = osLastError()
        cleanupClipboardProcess(process)
        return Result[string, string].err(
          "Failed to read the clipboard tool output: " & osErrorMsg(readErr)
        )
      if r == 0:
        # EOF with POLLERR is still clean EOF.
        break
      output.add(buf[0 ..< r])
      deadline = getMonoTime() + initDuration(milliseconds = timeoutMs)
      if output.len > maxReadSize:
        return outputTooLargeErr(process, maxReadSize)
      continue
    if (pfd.revents and (POLLHUP or POLLERR)) != 0:
      let r2 = read(fd, addr buf[0], buf.len)
      if r2 > 0:
        output.add(buf[0 ..< r2])
        deadline = getMonoTime() + initDuration(milliseconds = timeoutMs)
        if output.len > maxReadSize:
          return outputTooLargeErr(process, maxReadSize)
        continue
      elif r2 < 0:
        let errCode2 = osLastError().cint
        if errCode2 == EINTR:
          continue
        if errCode2 != EAGAIN and errCode2 != EWOULDBLOCK:
          let readErr2 = osLastError()
          cleanupClipboardProcess(process)
          return Result[string, string].err(
            "Failed to read the clipboard tool output: " & osErrorMsg(readErr2)
          )
      if (pfd.revents and POLLERR) != 0 and r2 != 0:
        cleanupClipboardProcess(process)
        return Result[string, string].err(
          "Failed to poll the clipboard tool: error on file descriptor"
        )
      break
    sleep(1)
    continue
  drainDiagnostics(errFd, toolStderr)
  let exitBound = min(deadline, hardDeadline)
  let waitHitTotalBound = hardDeadline <= deadline
  let waitBoundMs = if waitHitTotalBound: maxTotalMs else: timeoutMs
  let remainingWait = exitBound - getMonoTime()
  if remainingWait <= initDuration(milliseconds = 0):
    if output.len > 0:
      return dataDespiteDeadline(
        process,
        output,
        "EOF reached but deadline exceeded; returning complete data",
        toolStderr,
        hardDeadline = hardDeadline,
        acceptRunning = true,
      )
    return noDataOutcome(
      process, toolStderr, errFd, waitBoundMs, waitHitTotalBound, ExitGraceMs
    )
  let waitMs = max(1, ((remainingWait.inNanoseconds + 999_999) div 1_000_000).int)
  let exitDeadline = getMonoTime() + initDuration(milliseconds = waitMs)
  let exitCode = pollExitDraining(process, exitDeadline, errFd, toolStderr)
  drainDiagnostics(errFd, toolStderr)
  if exitCode == ExitStatusLost:
    if output.len > 0:
      cleanupClipboardProcess(process)
      logWarn("clipboard", "clipboard tool exit status lost; returning complete data")
      return Result[string, string].ok(sanitizeInvalidUtf8(output))
    return noDataOutcome(
      process, toolStderr, errFd, waitBoundMs, waitHitTotalBound, ExitGraceMs
    )
  if exitCode == -2:
    cleanupClipboardProcess(process)
    return Result[string, string].err("Failed to wait for the clipboard tool")
  if exitCode == -1:
    if output.len > 0:
      return dataDespiteDeadline(
        process,
        output,
        "tool hung after output; returning data despite timeout",
        toolStderr,
        hardDeadline = hardDeadline,
        acceptRunning = true,
      )
    return timedOutErr(process, waitBoundMs, waitHitTotalBound)
  if exitCode != 0:
    if output.len == 0:
      return emptySelection(exitCode, toolStderr)
    return exitCodeErr(exitCode, toolStderr)
  return Result[string, string].ok(sanitizeInvalidUtf8(output))

proc getClipboardCommand*(
    tool: ClipboardTool, operation: ClipboardOperation
): Option[seq[string]] =
  ## Command for clipboard read/write. Availability checked at runtime.
  case tool
  of cbtXclip:
    case operation
    of ClipboardOperation.read:
      return some(@["xclip", "-selection", "clipboard", "-o"])
    of ClipboardOperation.write:
      return some(@["xclip", "-selection", "clipboard", "-i"])
  of cbtXsel:
    case operation
    of ClipboardOperation.read:
      return some(@["xsel", "--clipboard", "--output"])
    of ClipboardOperation.write:
      return some(@["xsel", "--clipboard", "--input"])
  of cbtWlClipboard:
    case operation
    of ClipboardOperation.read:
      return some(@["wl-paste", "-n"])
    of ClipboardOperation.write:
      return some(@["wl-copy"])
  of cbtWin32yank:
    case operation
    of ClipboardOperation.read:
      return some(@["win32yank.exe", "-o", "--lf"])
    of ClipboardOperation.write:
      return some(@["win32yank.exe", "-i", "--crlf"])
  of cbtPbcopy:
    # macOS pbcopy/pbpaste
    case operation
    of ClipboardOperation.read:
      return some(@["pbpaste"])
    of ClipboardOperation.write:
      return some(@["pbcopy"])

proc getPrimarySelectionReadCommand*(tool: ClipboardTool): Option[seq[string]] =
  ## Command to read X11 PRIMARY selection.
  case tool
  of cbtXclip:
    return some(@["xclip", "-selection", "primary", "-o"])
  of cbtXsel:
    # xsel reads from PRIMARY by default (no --clipboard flag)
    return some(@["xsel", "--output"])
  of cbtWlClipboard:
    return some(@["wl-paste", "-n", "--primary"])
  of cbtWin32yank, cbtPbcopy:
    # Windows/macOS don't have PRIMARY selection; fall back to clipboard
    return getClipboardCommand(tool, ClipboardOperation.read)

proc runClipboardRead(
    tool: ClipboardTool, cmdOpt: Option[seq[string]], label: string
): Result[string, string] =
  ## Run clipboard read with bounded timeout; label used in errors.
  if cmdOpt.isNone:
    return Result[string, string].err("Clipboard tool not available: " & $tool)

  let cmd = cmdOpt.get()
  var process: Process = nil
  try:
    process =
      startProcess(cmd[0], args = cmd[1 ..^ 1], options = ClipboardProcessOptions)
    let readResult = readAllWithTimeout(process, ReadTimeoutMs)
    if readResult.isErr:
      return Result[string, string].err(
        "Failed to read from " & label & ": " & readResult.error
      )
    return readResult
  except CatchableError as e:
    return Result[string, string].err("Failed to read from " & label & ": " & e.msg)
  finally:
    if not process.isNil:
      try:
        process.close()
      except CatchableError:
        discard

proc readFromClipboardSync*(tool: ClipboardTool): Result[string, string] =
  ## Read system clipboard synchronously.
  runClipboardRead(
    tool, getClipboardCommand(tool, ClipboardOperation.read), "clipboard"
  )

proc readFromPrimarySelectionSync*(tool: ClipboardTool): Result[string, string] =
  ## Read X11 PRIMARY selection synchronously.
  runClipboardRead(tool, getPrimarySelectionReadCommand(tool), "primary selection")

proc getPrimarySelectionWriteCommand*(tool: ClipboardTool): Option[seq[string]] =
  ## Command to write X11 PRIMARY selection.
  case tool
  of cbtXclip:
    return some(@["xclip", "-selection", "primary", "-i"])
  of cbtXsel:
    # xsel writes to PRIMARY by default (no --clipboard flag)
    return some(@["xsel", "--input"])
  of cbtWlClipboard:
    return some(@["wl-copy", "--primary"])
  of cbtWin32yank, cbtPbcopy:
    return getClipboardCommand(tool, ClipboardOperation.write)

proc wlCopyExitedEarly(process: Process): Option[int] =
  ## Exit code if wl-copy already exited, none if still running.
  var i = 0
  while i < 5:
    let exitCode = process.peekExitCode()
    if exitCode != -1:
      return some(exitCode)
    sleep(10)
    inc i
  return none(int)

proc runClipboardWrite(
    tool: ClipboardTool,
    cmdOpt: Option[seq[string]],
    text: string,
    timeoutMs: int,
    label: string,
): Result[bool, string] =
  ## Run clipboard write with bounded timeout; label used in errors.
  ## ok(true)=terminated, ok(false)=still running.
  if cmdOpt.isNone:
    return Result[bool, string].err("Clipboard tool not available: " & $tool)

  let cmd = cmdOpt.get()
  let prefix = "Failed to write to " & label & ": "
  var process: Process = nil
  try:
    process =
      startProcess(cmd[0], args = cmd[1 ..^ 1], options = ClipboardProcessOptions)
    let started = getMonoTime()
    let deadline = started + initDuration(milliseconds = timeoutMs)
    var toolStderr = ToolDiagnostics()
    let errFd = process.diagnosticsFd()
    let writeRes = writeAllBounded(process, text, deadline, errFd, toolStderr)
    if writeRes.isErr:
      return Result[bool, string].err(prefix & writeRes.error)
    drainDiagnostics(errFd, toolStderr)
    if tool == cbtWlClipboard:
      let earlyExit = process.wlCopyExitedEarly()
      if earlyExit.isSome and earlyExit.get != 0:
        return Result[bool, string].err(
          prefix & "exit " & exitCodeDetail(earlyExit.get, toolStderr)
        )
      return Result[bool, string].ok(earlyExit.isSome)
    let graceDeadline = getMonoTime() + initDuration(milliseconds = ExitGraceMs)
    let exitDeadline = if graceDeadline > deadline: graceDeadline else: deadline
    let exitCode = waitForExitBounded(process, exitDeadline, errFd, toolStderr)
    drainDiagnostics(errFd, toolStderr)
    if exitCode == ExitStatusLost:
      logWarn("clipboard", "clipboard tool exit status lost after a completed write")
      return Result[bool, string].ok(true)
    if exitCode == -1:
      return Result[bool, string].err(
        prefix & "the tool did not exit within " &
          $(getMonoTime() - started).inMilliseconds & "ms and was killed"
      )
    if exitCode == -2:
      return Result[bool, string].err(prefix & "failed to wait for the clipboard tool")
    if exitCode == 0:
      return Result[bool, string].ok(true)
    return
      Result[bool, string].err(prefix & "exit " & exitCodeDetail(exitCode, toolStderr))
  except CatchableError as e:
    return Result[bool, string].err(prefix & e.msg)
  finally:
    if not process.isNil:
      try:
        process.close()
      except CatchableError:
        discard

proc writeToClipboardSync*(
    tool: ClipboardTool, text: string, timeoutMs: int = WriteTimeoutMs
): Result[bool, string] =
  ## Write system clipboard. ok(true)=terminated, ok(false)=still running.
  runClipboardWrite(
    tool,
    getClipboardCommand(tool, ClipboardOperation.write),
    text,
    timeoutMs,
    "clipboard",
  )

proc writeToPrimarySelectionSync*(
    tool: ClipboardTool, text: string, timeoutMs: int = WriteTimeoutMs
): Result[bool, string] =
  ## Write X11 PRIMARY selection. ok(true)=terminated, ok(false)=still running.
  runClipboardWrite(
    tool, getPrimarySelectionWriteCommand(tool), text, timeoutMs, "primary selection"
  )
