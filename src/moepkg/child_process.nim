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

## Starting a child process and waiting for it.
##
## On Linux chronos never starts a child: it changes the whole process's
## directory around the spawn, lets the child inherit descriptors that are not
## close-on-exec, and learns of the exit from SIGCHLD, which another thread's
## dispatcher can take first. The child is started here, by `posix_spawnp`
## where libc can do everything asked of it in the child, and by fork and exec
## otherwise. Either way it enters its working directory itself, reads
## /dev/null or a pipe, holds no descriptor of moe's, and leads a process group
## of its own. The start is over when the call returns. The exit is read from
## a pidfd, or polled for.
##
## Only `release` reaps. Until then the pid, and the number of the group it
## leads, stay the child's even after it has exited, so a signal never reaches
## somebody else's process and a kill after a timeout still takes out what the
## command left running in its group.
##
## Elsewhere chronos starts the child and its one wait reaps it. A signal can
## then race that reap, and the start changes moe's directory for its
## duration.

import std/[options, oserrors]

import pkg/[results, chronos]
import pkg/chronos/[asyncproc, streams/asyncstream]

when defined(posix):
  import std/posix

when defined(linux):
  import std/locks
  from pkg/chronos/osutils import DescriptorFlag, createOsPipe
  import fork_exec_linux, logger, posix_spawn_setup, posix_wait

type
  ChildStdin* = enum
    csNull ## /dev/null: nothing to read, and never the terminal.
    csPipe ## A pipe the caller writes through `stdinStream`.

  ChildStderr* = enum
    ceMerge ## Into standard output.
    cePipe ## A pipe of its own, read through `stderrStream`.

  ChildFate* = enum
    ## What is known of a child, and so what its pid may still be used for.
    cfRunning ## Not seen to exit.
    cfExited
      ## Exited, unreaped: the pid and its group's number are still the
      ## child's, so a signal to them reaches nobody else.
    cfReaped ## Reaped: the pid may be somebody else's now.
    cfUnknown
      ## Waiting for it failed, or it outlived its kill and was left to be
      ## reaped later: how it ended is not known, and the pid is not this
      ## handle's to use.

  ChildEnd = object
    case fate: ChildFate
    of cfExited, cfReaped:
      status: int ## How it ended, as a shell reports it.
    of cfRunning, cfUnknown:
      discard

  ChildProcess* = ref object ## A started child and the one record of its life.
    ending: ChildEnd
    releasing: FutureBase ## The one `release`; nil until it starts.
    stdinMode: ChildStdin
    stderrMode: ChildStderr
    when defined(linux):
      childPid: int
      pidfd: cint ## -1 without one, or once closed.
      exitReady: Future[void]
        ## Completes once the pidfd says the child exited, or once the pidfd
        ## is closed; shared by every waiter. nil until the first wait.
      stdinWriter: AsyncStreamWriter
      stdoutReader: AsyncStreamReader
      stderrReader: AsyncStreamReader
    else:
      process: AsyncProcessRef
      exitWait: FutureBase
        ## The one wait on `process`, which reaps it: chronos refuses a second
        ## at once, and a reap outside it leaves it waiting forever.

const
  ReleaseGrace = 2.seconds
    ## How long `release` waits for a killed child before leaving it to be
    ## reaped later.
  PollFirst = 10.milliseconds
  PollMax = 250.milliseconds

proc pid*(c: ChildProcess): int =
  when defined(linux): c.childPid else: c.process.pid

proc fate*(c: ChildProcess): ChildFate =
  ## As last learnt; `running` and the waits learn more.
  c.ending.fate

proc released*(c: ChildProcess): bool =
  ## Whether `release` has begun: the pipes are closed or closing.
  not c.releasing.isNil

proc exitCode*(c: ChildProcess): Option[int] =
  ## How the child ended, as a shell reports it; none until then, or if that
  ## is not known.
  case c.ending.fate
  of cfExited, cfReaped:
    some(c.ending.status)
  of cfRunning, cfUnknown:
    none(int)

proc stdinStream*(c: ChildProcess): AsyncStreamWriter =
  ## nil unless standard input is a pipe.
  if c.stdinMode != csPipe:
    return nil
  when defined(linux):
    c.stdinWriter
  else:
    c.process.stdinStream()

proc stdoutStream*(c: ChildProcess): AsyncStreamReader =
  when defined(linux):
    c.stdoutReader
  else:
    c.process.stdoutStream()

proc stderrStream*(c: ChildProcess): AsyncStreamReader =
  ## nil when standard error is merged into standard output.
  if c.stderrMode != cePipe:
    return nil
  when defined(linux):
    c.stderrReader
  else:
    c.process.stderrStream()

when defined(linux):
  proc observe(c: ChildProcess) =
    ## Learn whether a running child has exited, without reaping it.
    if c.ending.fate != cfRunning:
      return
    var info: SigInfo
    if waitidRetrying(c.childPid, info, WEXITED or WNOHANG or WNOWAIT) != 0:
      # Not moe's child any more: nothing about it can be learnt now.
      c.ending = ChildEnd(fate: cfUnknown)
    elif info.si_pid != Pid(0):
      c.ending = ChildEnd(fate: cfExited, status: decodeSiginfo(info))

  proc reap(c: ChildProcess) =
    ## Reap a child seen to exit.
    if c.ending.fate != cfExited:
      return
    var info: SigInfo
    discard waitidRetrying(c.childPid, info, WEXITED or WNOHANG)
    c.ending = ChildEnd(fate: cfReaped, status: c.ending.status)

  var
    stragglerLock: Lock
    stragglers: array[32, int]
      ## Children `release` killed that had not exited by its grace, reaped by
      ## whichever start or release comes next, on any thread. 0 is free.
  initLock(stragglerLock)

  proc reapStragglers() =
    withLock stragglerLock:
      for pid in stragglers.mitems:
        if pid != 0:
          var info: SigInfo
          if waitidRetrying(pid, info, WEXITED or WNOHANG) != 0 or info.si_pid != Pid(0):
            pid = 0

  proc leaveToReaper(c: ChildProcess) =
    ## Hand an unreaped child over to `reapStragglers`, which owns its pid
    ## from then on.
    var tracked = false
    withLock stragglerLock:
      for slot in stragglers.mitems:
        if slot == 0:
          slot = c.childPid
          tracked = true
          break
    if not tracked:
      logWarn "child_process",
        "Process " & $c.childPid & " outlived its kill with no room to track it: " &
          "it stays a zombie until moe exits"
    c.ending = ChildEnd(fate: cfUnknown)

  proc watchExit(c: ChildProcess): Result[Future[void], OSErrorCode] =
    ## `exitReady`, registering the pidfd with the dispatcher only once.
    if not c.exitReady.isNil:
      return ok(c.exitReady)
    let
      fd = AsyncFD(c.pidfd)
      ready = newFuture[void]("child.exit")
    proc onExit(udata: pointer) {.gcsafe, raises: [].} =
      discard removeReader2(fd)
      if not ready.finished:
        ready.complete()

    ?register2(fd)
    let added = addReader2(fd, onExit)
    if added.isErr:
      discard unregister2(fd)
      return err(added.error)
    c.exitReady = ready
    ok(ready)

  proc closePidfd(c: ChildProcess) =
    ## Let go of the pidfd. Waiters on it go on by polling.
    if c.pidfd < 0:
      return
    if not c.exitReady.isNil:
      # Out of the dispatcher before the number can be reused.
      discard removeReader2(AsyncFD(c.pidfd))
      discard unregister2(AsyncFD(c.pidfd))
      if not c.exitReady.finished:
        c.exitReady.complete()
    discard posix.close(c.pidfd)
    c.pidfd = -1

  proc running*(c: ChildProcess): bool =
    ## Whether the child is known to run still.
    c.observe()
    c.ending.fate == cfRunning

  proc signal(c: ChildProcess, sig: cint) =
    ## Signal the child and everything in the process group it leads, as long
    ## as the pid is still its own.
    c.observe()
    if c.ending.fate notin {cfRunning, cfExited}:
      return
    let pid = Pid(c.childPid)
    # The child by its pid too only when it has left the group, so it is not
    # signalled twice.
    if posix.kill(-pid, sig) != 0 or getpgid(pid) != pid:
      discard posix.kill(pid, sig)

  proc terminate*(c: ChildProcess) =
    ## SIGTERM the child and everything it started.
    c.signal(SIGTERM)

  proc kill*(c: ChildProcess) =
    ## SIGKILL the child and everything it started.
    c.signal(SIGKILL)

  proc waitForExit*(
      c: ChildProcess
  ): Future[int] {.async: (raises: [AsyncProcessError, CancelledError]).} =
    ## Wait for the child to exit and return how it ended. Any number of
    ## waiters may overlap. Raises when how it ended is not known.
    c.observe()
    if c.ending.fate == cfRunning and c.pidfd >= 0:
      let ready = c.watchExit()
      if ready.isOk:
        await ready.get.join()
        c.observe()
    var pause = PollFirst
    # Without a pidfd, or once it is closed or refused by the dispatcher.
    while c.ending.fate == cfRunning:
      await sleepAsync(pause)
      pause = min(pause * 2, PollMax)
      c.observe()
    case c.ending.fate
    of cfExited, cfReaped:
      return c.ending.status
    of cfRunning, cfUnknown:
      raise newException(AsyncProcessError, "How the process ended is not known")

  proc closePipes(c: ChildProcess) {.async: (raises: []).} =
    if not c.stdinWriter.isNil:
      await c.stdinWriter.closeWait()
      await c.stdinWriter.tsource.closeWait()
    if not c.stdoutReader.isNil:
      await c.stdoutReader.closeWait()
      await c.stdoutReader.tsource.closeWait()
    if not c.stderrReader.isNil:
      await c.stderrReader.closeWait()
      await c.stderrReader.tsource.closeWait()

  proc settle(c: ChildProcess) {.async: (raises: []).} =
    ## The one release of `c`.
    if c.running():
      c.kill()
      try:
        discard await c.waitForExit().wait(ReleaseGrace)
      except AsyncTimeoutError, AsyncProcessError, CancelledError:
        discard
    await c.closePipes()
    c.closePidfd()
    case c.ending.fate
    of cfExited:
      c.reap()
    of cfRunning:
      # Alive past a SIGKILL: uninterruptible sleep.
      c.leaveToReaper()
    of cfReaped, cfUnknown:
      discard
    reapStragglers()

else:
  proc waitChronos(c: ChildProcess) {.async: (raises: []).} =
    try:
      let status = await c.process.waitForExit()
      c.ending = ChildEnd(fate: cfReaped, status: status)
    except AsyncProcessError, CancelledError:
      c.ending = ChildEnd(fate: cfUnknown)

  proc startWait(c: ChildProcess) =
    if c.exitWait.isNil and c.ending.fate == cfRunning:
      c.exitWait = c.waitChronos()

  proc running*(c: ChildProcess): bool =
    ## Whether the child is known to run still. Learnt from the one wait, so
    ## the answer lags the exit by a turn of the dispatcher.
    c.startWait()
    c.ending.fate == cfRunning

  proc signal(c: ChildProcess, sig: cint) =
    if c.ending.fate != cfRunning:
      return
    when defined(posix):
      let pid = Pid(c.process.pid)
      if posix.kill(-pid, sig) != 0 or getpgid(pid) != pid:
        discard posix.kill(pid, sig)
    else:
      discard (if sig == 9: c.process.kill() else: c.process.terminate())

  proc terminate*(c: ChildProcess) =
    ## SIGTERM the child and everything it started.
    c.signal(15)

  proc kill*(c: ChildProcess) =
    ## SIGKILL the child and everything it started.
    c.signal(9)

  proc waitForExit*(
      c: ChildProcess
  ): Future[int] {.async: (raises: [AsyncProcessError, CancelledError]).} =
    ## Wait for the child to exit and return how it ended. Any number of
    ## waiters may overlap. Raises when how it ended is not known.
    c.startWait()
    if not c.exitWait.isNil:
      # Joined, not awaited: one waiter's cancellation is not the others'.
      await c.exitWait.join()
    case c.ending.fate
    of cfExited, cfReaped:
      return c.ending.status
    of cfRunning, cfUnknown:
      raise newException(AsyncProcessError, "How the process ended is not known")

  proc settle(c: ChildProcess) {.async: (raises: []).} =
    if c.running():
      c.kill()
      try:
        discard await c.waitForExit().wait(ReleaseGrace)
      except AsyncTimeoutError, AsyncProcessError, CancelledError:
        discard
    # A wait still pending reaps the child once it exits.
    await c.process.closeWait()

proc release*(c: ChildProcess) {.async: (raises: []).} =
  ## Let the child go: stopped if it still runs, reaped, pipes closed. A child
  ## that outlives the kill by `ReleaseGrace` (uninterruptible sleep) is
  ## reaped once it exits. Every call waits for the one release, which no
  ## cancellation cuts short.
  if c.releasing.isNil:
    c.releasing = c.settle()
  await noCancel c.releasing.join()

when defined(linux):
  # The syscall number differs between architectures; the header knows it.
  {.
    emit: """/*TYPESECTION*/
#include <errno.h>
#include <sys/syscall.h>
#include <unistd.h>
static int moePidfdOpen(int pid) {
  /* Android's seccomp may kill a process for asking. */
#if defined(SYS_pidfd_open) && !defined(__ANDROID__)
  return (int)syscall(SYS_pidfd_open, pid, 0);
#else
  errno = ENOSYS;
  return -1;
#endif
}
"""
  .}
  proc moePidfdOpen(pid: cint): cint {.importc, nodecl.}

  const forkAlways = defined(moeSpawnViaFork)
    ## Start every child with fork and exec, so the tests exercise both ways.

  proc posixSpawnSuffices(workingDir: string): bool =
    ## Whether libc's `posix_spawn` can do all a start needs in the child.
    not forkAlways and canCloseInherited() and (
      workingDir.len == 0 or canChdirInChild()
    )

  proc spawnWithPosixSpawn(
      command, workingDir: string, args: seq[string], input, output, errors: cint
  ): Result[Pid, OSErrorCode] =
    proc addActions(actions: var Tposix_spawn_file_actions): cint =
      result = posix_spawn_file_actions_adddup2(actions, input, 0)
      if result == 0:
        result = posix_spawn_file_actions_adddup2(actions, output, 1)
      if result == 0:
        result = posix_spawn_file_actions_adddup2(actions, errors, 2)
      if result == 0 and workingDir.len > 0:
        result = chdirInChild(actions, workingDir)
      if result == 0:
        result = closeInherited(actions)

    var pid: Pid
    let rc = spawnChild(pid, command, @[command] & args, ownGroup = true, addActions)
    if rc != 0:
      return err(OSErrorCode(rc))
    ok(pid)

  proc closeIfOpen(fd: var cint) =
    if fd >= 0:
      discard posix.close(fd)
      fd = -1

  proc transportOf(fd: var cint): Result[StreamTransport, OSErrorCode] =
    ## The chronos transport over the parent's end of a pipe, which owns the
    ## descriptor from then on.
    let transport = ?fromPipe2(AsyncFD(fd))
    fd = -1
    ok(transport)

  proc makePipe(
      pipe: var array[2, cint], parentReads: bool
  ): Result[void, OSErrorCode] =
    ## Close-on-exec from the start: another thread may start a child meanwhile.
    let
      parent = {DescriptorFlag.CloseOnExec, DescriptorFlag.NonBlock}
      child = {DescriptorFlag.CloseOnExec}
    let fds =
      ?(if parentReads: createOsPipe(parent, child)
      else: createOsPipe(child, parent))
    pipe = [fds.read, fds.write]
    ok()

  proc startChild*(
      command, workingDir: string,
      args: seq[string],
      stdinMode = csNull,
      stderrMode = ceMerge,
  ): Result[ChildProcess, string] =
    ## Start `command` (looked up on PATH) in `workingDir`, or in moe's own
    ## when empty, as the leader of a process group of its own. The child
    ## exists when this returns, and its handle must be released.
    reapStragglers()
    var
      output: array[2, cint] = [cint(-1), cint(-1)]
      errors: array[2, cint] = [cint(-1), cint(-1)]
      input: array[2, cint] = [cint(-1), cint(-1)]
    template closeAll() =
      for fd in output.mitems:
        closeIfOpen(fd)
      for fd in errors.mitems:
        closeIfOpen(fd)
      for fd in input.mitems:
        closeIfOpen(fd)

    template failWith(what: string, code: OSErrorCode) =
      closeAll()
      return err(what & ": " & osErrorMsg(code))

    template pipeOrFail(pipe: var array[2, cint], parentReads: bool) =
      let made = makePipe(pipe, parentReads)
      if made.isErr:
        failWith("Unable to create a pipe", made.error)

    pipeOrFail(output, parentReads = true)
    if stderrMode == cePipe:
      pipeOrFail(errors, parentReads = true)
    case stdinMode
    of csPipe:
      pipeOrFail(input, parentReads = false)
    of csNull:
      input[0] = posix.open("/dev/null", O_RDONLY or O_CLOEXEC)
      if input[0] < 0:
        # Better no command than one reading the keys meant for moe.
        failWith("Unable to open /dev/null", osLastError())

    let
      errorTarget =
        if stderrMode == cePipe:
          errors[1]
        else:
          output[1]
      spawned =
        if posixSpawnSuffices(workingDir):
          spawnWithPosixSpawn(
            command, workingDir, args, input[0], output[1], errorTarget
          )
        else:
          forkExec(command, workingDir, args, input[0], output[1], errorTarget)
    # The child's ends are the child's now.
    closeIfOpen(output[1])
    closeIfOpen(errors[1])
    closeIfOpen(input[0])
    if spawned.isErr:
      failWith("Unable to start a process", spawned.error)

    let pid = spawned.get
    let child = ChildProcess(
      childPid: int(pid),
      # -1 on a kernel without pidfds (before 5.3): the exit is polled for.
      pidfd: moePidfdOpen(cint(pid)),
      stdinMode: stdinMode,
      stderrMode: stderrMode,
    )
    var failure = OSErrorCode(0)
    let transport = transportOf(output[0])
    if transport.isOk:
      child.stdoutReader = newAsyncStreamReader(transport.get)
    else:
      failure = transport.error
    if stderrMode == cePipe and failure == OSErrorCode(0):
      let transport = transportOf(errors[0])
      if transport.isOk:
        child.stderrReader = newAsyncStreamReader(transport.get)
      else:
        failure = transport.error
    if stdinMode == csPipe and failure == OSErrorCode(0):
      let transport = transportOf(input[1])
      if transport.isOk:
        child.stdinWriter = newAsyncStreamWriter(transport.get)
      else:
        failure = transport.error
    if failure != OSErrorCode(0):
      # Started, but not in a state to be run: stopped, reaped and released in
      # the background, with the streams made so far.
      closeAll()
      asyncSpawn child.release()
      return err("Unable to reach the process: " & osErrorMsg(failure))
    ok(child)

else:
  proc startChild*(
      command, workingDir: string,
      args: seq[string],
      stdinMode = csNull,
      stderrMode = ceMerge,
  ): Result[ChildProcess, string] =
    ## Start `command` (looked up on PATH) in `workingDir`, or in moe's own
    ## when empty, as the leader of a process group of its own. The child
    ## exists when this returns, and its handle must be released.
    var options = {AsyncProcessOption.UsePath, AsyncProcessOption.ProcessGroup}
    if stderrMode == ceMerge:
      options.incl AsyncProcessOption.StdErrToStdOut
    var stdinHandle = ProcessStreamHandle.init()
    var devNull: cint = -1
    when defined(posix):
      if stdinMode == csNull:
        devNull = posix.open("/dev/null", O_RDONLY or O_CLOEXEC)
        if devNull < 0:
          # Better no command than one reading the keys meant for moe.
          return err("Unable to open /dev/null: " & osErrorMsg(osLastError()))
        stdinHandle = ProcessStreamHandle.init(AsyncFD(devNull))
    if stdinMode == csPipe:
      stdinHandle = AsyncProcess.Pipe
    defer:
      when defined(posix):
        if devNull >= 0:
          discard posix.close(devNull)
    let started = startProcess(
      command,
      workingDir,
      args,
      options = options,
      stdinHandle = stdinHandle,
      stdoutHandle = AsyncProcess.Pipe,
      stderrHandle =
        if stderrMode == cePipe:
          AsyncProcess.Pipe
        else:
          ProcessStreamHandle.init(),
    )
    # chronos finishes a start that succeeds before returning it; only its
    # failure path waits, to close the pipes it made.
    if not started.finished:
      return err("Unable to start a process")
    if started.failed:
      return err(started.error.msg)
    ok(
      ChildProcess(process: started.value, stdinMode: stdinMode, stderrMode: stderrMode)
    )
