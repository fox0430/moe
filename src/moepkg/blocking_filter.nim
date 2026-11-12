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

## Running a text filter while the caller blocks, for a command that has to
## finish where it was given: what comes after it (the rest of a mapping or a
## macro) runs after it, as in Vim. The editor's event loop does not run
## meanwhile, so nothing else happens in the middle of the caller's command.
##
## The command runs on a worker thread with a dispatcher of its own, through
## the same `startFilterProcess` and `filterOutput` as every other filter, so
## the timeout, kill and reap contract stays in one place. The thread starts
## with the first run and is never joined: between runs it waits, and its
## dispatcher keeps reaping what a run released in the background.

import std/[atomics, os]

import pkg/[results, chronos]
import pkg/chronos/threadsync

import background_process, signal_watcher

when defined(windows):
  type DoneSignal = object
    signal: ThreadSignalPtr

else:
  from std/posix import TPollfd, Tnfds, POLLIN, poll, read, write, errno, EINTR
  from pkg/chronos/osutils import createOsPipe, closeFd, AsyncDescriptorDefault

  type DoneSignal = object
    ## A pipe waited for with `poll`. chronos' `waitSync` waits with `select`,
    ## which cannot take a descriptor numbered `FD_SETSIZE` or more.
    readFd*, writeFd*: cint

const BlockingWaitSlice* = 20.milliseconds
  ## How often the caller gets a turn while the command runs, by default.

const LongestWaitSlice = 1.seconds
  ## The longest wait between turns. A deadly signal is noticed only at a turn,
  ## and the signal watcher gives the loop seconds to answer it.

proc newDoneSignal(): Result[DoneSignal, string] =
  when defined(windows):
    ok DoneSignal(signal: ?ThreadSignalPtr.new())
  else:
    let fds = createOsPipe(AsyncDescriptorDefault, AsyncDescriptorDefault).valueOr:
      return err(osErrorMsg(error))
    ok DoneSignal(readFd: fds.read, writeFd: fds.write)

proc close(s: DoneSignal) =
  when defined(windows):
    discard s.signal.close()
  else:
    discard closeFd(s.readFd)
    discard closeFd(s.writeFd)

proc fire(s: DoneSignal) =
  ## A lost fire costs the waiter one timeout, so failures are ignored.
  when defined(windows):
    discard s.signal.fireSync()
  else:
    var b = 1'u8
    while write(s.writeFd, addr b, 1) < 0 and errno == EINTR:
      discard

proc waitFired(s: DoneSignal, timeout: Duration): bool =
  ## Whether `s` fired within `timeout`, resetting it if so. Returns early,
  ## false, when interrupted; sleeps the whole `timeout` if it cannot wait.
  when defined(windows):
    let woke = s.signal.waitSync(timeout)
    if woke.isErr:
      sleep(timeout.milliseconds.int)
      return false
    woke.get
  else:
    var pfd = TPollfd(fd: s.readFd, events: POLLIN)
    let ready = poll(addr pfd, Tnfds(1), cint(timeout.milliseconds))
    if ready < 0 and errno != EINTR:
      sleep(timeout.milliseconds.int)
    if ready <= 0:
      return false
    # One byte per run, so this takes every fire in practice; a byte left over
    # only wakes the next wait early.
    var buf: array[64, byte]
    discard read(s.readFd, addr buf, buf.len)
    true

type
  FilterJob = object
    command*: BackgroundProcessCommand
    input*: string
    timeout*: Duration
    limit*: int
    stopAsked*: Atomic[bool]
    finished: Atomic[bool]
    outcome*: FilterProcessResult

  Worker = object
    thread: Thread[ptr Worker]
    wake: ThreadSignalPtr ## For the worker: a job was posted or its stop asked.
    done: DoneSignal ## For the caller: the posted job is over.
    posted: Atomic[ptr FilterJob]
    busy: Atomic[bool] ## A caller holds the worker.
    started: bool ## Only touched by the caller holding the worker.

var worker: Worker

proc nextWake(w: ptr Worker) {.async: (raises: [CancelledError]).} =
  ## The next wake-up, or a slice later if the signal cannot be waited for.
  ## What woke the worker is read from the job, so polling loses nothing.
  try:
    await w.wake.wait()
  except AsyncError:
    await sleepAsync(BlockingWaitSlice)

proc runJob(w: ptr Worker, job: ptr FilterJob) {.async: (raises: []).} =
  if job.stopAsked.load(moAcquire):
    # Stopped before it started: the command never runs.
    job.outcome =
      FilterProcessResult.err filterError(ffCancelled, "The command was cancelled")
    return
  let started = startFilterProcess(job.command)
  if started.isErr:
    job.outcome = FilterProcessResult.err filterError(ffStartFailed, started.error)
    return

  let stop = JobStop()
  proc watchStop() {.async: (raises: []).} =
    try:
      while not job.stopAsked.load(moAcquire):
        await w.nextWake()
      stop.request()
    except CancelledError:
      discard

  let watcher = watchStop()
  job.outcome =
    await started.get.filterOutput(move job.input, job.timeout, job.limit, stop)
  await watcher.cancelAndWait()

proc serve(w: ptr Worker) {.async: (raises: []).} =
  while true:
    let job = w.posted.exchange(nil, moAcquireRelease)
    if job.isNil:
      try:
        await w.nextWake()
      except CancelledError:
        return
      continue
    await w.runJob(job)
    # The job is the caller's again from here.
    job.finished.store(true, moRelease)
    w.done.fire()

proc workerThread(w: ptr Worker) {.thread.} =
  waitFor w.serve()

proc startWorker(): Result[void, string] =
  ## Start the worker unless it runs. Only for the caller holding it.
  if worker.started:
    return ok()
  worker.wake = ?ThreadSignalPtr.new()
  let done = newDoneSignal()
  if done.isErr:
    discard worker.wake.close()
    return err(done.error)
  worker.done = done.get
  try:
    createThread(worker.thread, workerThread, addr worker)
  except ResourceExhaustedError as e:
    discard worker.wake.close()
    worker.done.close()
    return err(e.msg)
  worker.started = true
  ok()

proc runFilterBlocking*(
    command: BackgroundProcessCommand,
    input: sink string,
    timeout: Duration,
    limit: int,
    onWait: proc(): bool {.gcsafe, raises: [].} = nil,
    slice = BlockingWaitSlice,
): FilterProcessResult =
  ## Run `command` as a text filter, as `startFilterProcess` and `filterOutput`
  ## do, and return once it is over. One run at a time: a run asked for while
  ## another waits fails to start.
  ##
  ## `onWait` runs about every `slice` while the command does, on the calling
  ## thread. Returning true stops the command, as Ctrl-C does in Vim, and the
  ## result is `ffCancelled`; it keeps being called until the command is gone,
  ## and asking again does nothing. A stop asked once the command is over
  ## comes too late, and its result stands. It must not start another run: as
  ## in Vim, keys typed meanwhile wait until the command is over. A `slice` is
  ## taken as at least a millisecond and at most a second. Without `onWait`
  ## and a timeout, a command that never ends blocks the caller until a deadly
  ## signal comes.
  ##
  ## A deadly signal taken for the event loop stops the command too: the loop
  ## cannot answer it before the caller is back, and the signal watcher would
  ## end moe with the command left running.
  let slice = slice.clamp(1.milliseconds, LongestWaitSlice)

  template failed(message: string): FilterProcessResult =
    FilterProcessResult.err filterError(ffStartFailed, message)

  var free = false
  if not worker.busy.compareExchange(free, true, moAcquire):
    return failed("Another command is being waited for")
  defer:
    worker.busy.store(false, moRelease)
  let ready = startWorker()
  if ready.isErr:
    return failed("Unable to start a thread for the command: " & ready.error)

  var job = FilterJob(command: command, input: input, timeout: timeout, limit: limit)
  if takenSignal() != 0:
    job.stopAsked.store(true, moRelease)
  worker.posted.store(addr job, moRelease)
  while not job.finished.load(moAcquire):
    if not worker.posted.load(moAcquire).isNil or job.stopAsked.load(moAcquire):
      # Again every turn: the worker never retries a lost wake-up, and an
      # extra one is harmless.
      discard worker.wake.fireSync()
    if worker.done.waitFired(slice):
      continue
    if (not onWait.isNil and onWait()) or takenSignal() != 0:
      job.stopAsked.store(true, moRelease)

  move job.outcome
