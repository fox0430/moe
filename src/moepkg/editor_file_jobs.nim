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

## Serializing the external commands that read or rewrite one file.
##
## One write can start a formatter hook, a build and a syntax check at once on
## the same path, so the compiler might read the file while the formatter
## truncates it. Each command claims the file first and releases it when done.
## The claim is per path, not per buffer: one file can be open twice.

import std/[monotimes, options, os, tables]

# `times` wholesale would shadow chronos's `milliseconds` below.
from std/times import inSeconds

import pkg/chronos

import types/editor_types
import background_process, editor_notify, quick_run_utils

type
  FileJobClaim* = tuple[key: string, ticket: uint64, granted: bool]
    ## What `claimFileJob` returns: the file claimed, the queue ticket that
    ## `releaseFileJob` gives up, and whether the guarded work may run. An empty
    ## key claimed nothing, which a pathless command still treats as granted.

  FileJobGiveUp* = proc(): bool {.gcsafe, raises: [].}
    ## Polled while a command waits for a file: true abandons the wait and
    ## refuses the claim.
    ##
    ## Without it, a command queued behind a `timeout = 0` hook would ignore
    ## `:jobs!` until `FileJobMaxWaitSeconds` runs out.

const
  NoCommandEpoch* = high(uint64)
    ## The epoch of work `:jobs!` cannot stop: a deferred write, or a claim taken
    ## in tests. The counter only counts up from zero, so it never reaches this.

  FileJobPollInterval = 10.milliseconds
    ## How often a waiting command re-checks; precision does not matter much,
    ## since serialized runs last hundreds of milliseconds.

  FileJobWaitNoticeSeconds = 5
    ## How long a command waits before reporting, so an ordinary hand-off stays
    ## quiet while a long wait is explained.
  FileJobMaxWaitSeconds = 120
    ## How long it waits at all. A `timeout = 0` hook can hold its file for the
    ## rest of the session; giving up instead keeps one wedged command from
    ## blocking everything queued behind it. The command that gave up does not
    ## run, so nothing overlaps the current holder.

proc commandEpoch*(e: Editor): uint64 =
  ## The epoch a command captures when spawned and passes to every later check.
  e.state.commandEpoch

proc commandsStoppedSince*(e: Editor, epoch: uint64): bool =
  ## Whether the user has stopped the external commands since `epoch` was taken,
  ## so that stopping also reaches work already running.
  epoch != NoCommandEpoch and e.state.commandEpoch != epoch

proc jobKey(path: string): string {.raises: [].} =
  ## The claim key: different spellings of one file must collide.
  if path.len == 0:
    return ""
  try:
    normalizedPath(absolutePath(path))
  except ValueError, OSError:
    # No current directory to resolve against: a relative path then collides
    # only with the same spelling, still better than no claim.
    normalizedPath(path)

proc elapsedText(startedAt: MonoTime): string =
  ## How long a command has been running, at human resolution.
  let secs = (getMonoTime() - startedAt).inSeconds
  if secs < 60:
    $secs & "s"
  else:
    $(secs div 60) & "m" & $(secs mod 60) & "s"

proc waitNotice*(e: Editor, path: string): string =
  ## Who holds `path`, for a command that waited long enough to be told.
  let key = jobKey(path)
  var holder = "Another command"
  block found:
    for running in e.runningBackgroundProcesses:
      if running.path.len > 0 and jobKey(running.path) == key:
        let name = if running.label.len > 0: running.label else: "A command"
        holder = name & " (" & elapsedText(running.startedAt) & ")"
        break found
    for qr in e.runningQuickRunProcesses:
      if qr.filePath.len > 0 and jobKey(qr.filePath) == key:
        holder = "QuickRun (" & elapsedText(qr.startedAt) & ")"
        break found
  "Waiting for " & holder & " on " & path & " (:jobs)"

proc releaseFileJob*(e: Editor, claim: FileJobClaim) =
  ## Give back what `claimFileJob` returned. An empty key claimed nothing.
  if claim.key.len == 0 or not e.state.fileJobs.hasKey(claim.key):
    return

  var waiting = e.state.fileJobs.getOrDefault(claim.key)
  for i, ticket in waiting:
    if ticket == claim.ticket:
      waiting.delete(i)
      break
  if waiting.len == 0:
    e.state.fileJobs.del(claim.key)
  else:
    e.state.fileJobs[claim.key] = waiting

proc claimFileJob*(
    e: Editor, path: string, giveUp: FileJobGiveUp = nil, epoch = NoCommandEpoch
): Future[FileJobClaim] {.async: (raises: []).} =
  ## Wait until no other command holds `path`, then claim it. Returns the claim
  ## to hand to `releaseFileJob` and whether the work may go ahead; a claim
  ## dropped, given up on or waited too long is refused rather than granted
  ## late.
  ##
  ## The file passes in arrival order, not by poll timing: a write queues its
  ## hooks before the build and the checker so they read what the hooks left,
  ## which only holds if the queue keeps its order.
  let key = jobKey(path)
  if key.len == 0:
    return ("", 0'u64, true)

  e.state.nextFileJobTicket.inc
  let ticket = e.state.nextFileJobTicket
  # Queued before the wait, so a later arrival cannot overtake this one.
  e.state.fileJobs.mgetOrPut(key, @[]).add ticket

  let waitingSince = getMonoTime()
  var reported = false
  while true:
    if giveUp != nil and giveUp():
      # Checked before the first look too: the work may have been abandoned
      # while this was queued.
      e.releaseFileJob((key, ticket, true))
      return ("", 0'u64, false)

    if e.commandsStoppedSince(epoch):
      # A stopped command may still sit at its queue's head, which `:jobs!`
      # leaves in place, so the claim is refused here as well.
      e.releaseFileJob((key, ticket, true))
      return ("", 0'u64, false)

    let waiting = e.state.fileJobs.getOrDefault(key)
    let place = waiting.find(ticket)
    if place < 0:
      # The ticket is gone, so `:jobs!` dropped the whole queue with it.
      return ("", 0'u64, false)
    if place == 0:
      break

    try:
      await sleepAsync(FileJobPollInterval)
    except CatchableError:
      # Cancelled: leave the queue instead of holding up everyone behind us.
      e.releaseFileJob((key, ticket, true))
      return ("", 0'u64, false)

    let waited = (getMonoTime() - waitingSince).inSeconds
    if waited >= FileJobMaxWaitSeconds:
      e.releaseFileJob((key, ticket, true))
      e.notify(
        "Gave up waiting for " & path & " after " & $FileJobMaxWaitSeconds & "s (:jobs)",
        nlWarning,
      )
      return ("", 0'u64, false)
    # Reported once, not every poll, so a long wait does not flood the status
    # line.
    if not reported and waited >= FileJobWaitNoticeSeconds:
      reported = true
      e.notify(e.waitNotice(path), nlWarning)

  return (key, ticket, true)

template withFileJob*(
    e: Editor, path: string, giveUp: FileJobGiveUp, epoch: uint64, body: untyped
) =
  ## Run `body` holding a claim on `path`; skipped when the claim is refused.
  ## Only usable inside an async proc: the claim itself waits.
  ##
  ## `giveUp` lets queued work the user abandoned leave the queue, and `epoch`
  ## is what the caller captured when spawned, so a `:jobs!` in between refuses
  ## the claim instead of starting the body.
  let claimedFileJob = await claimFileJob(e, path, giveUp, epoch)
  if claimedFileJob.granted:
    try:
      body
    finally:
      e.releaseFileJob(claimedFileJob)

template withFileJob*(e: Editor, path: string, epoch: uint64, body: untyped) =
  ## `withFileJob` for work that can only be given up on by `:jobs!`.
  withFileJob(e, path, nil, epoch, body)

template withFileJob*(e: Editor, path: string, body: untyped) =
  ## `withFileJob` for work that cannot be given up on once queued.
  withFileJob(e, path, nil, NoCommandEpoch, body)

proc runningCommands*(e: Editor): seq[string] =
  ## One line per running external command, plus a count of those queued behind
  ## them. Commands hold their file until they exit, so this makes the queue
  ## visible.
  for running in e.runningBackgroundProcesses:
    let name = if running.label.len > 0: running.label else: "Command"
    var line = name & " (" & elapsedText(running.startedAt) & ")"
    if running.path.len > 0:
      line &= ": " & running.path
    result.add line

  for qr in e.runningQuickRunProcesses:
    result.add "QuickRun (" & elapsedText(qr.startedAt) & "): " & qr.filePath

  # One holder per file, so everything behind it is waiting for its turn.
  var waiting = 0
  for _, tickets in e.state.fileJobs:
    waiting += max(0, tickets.len - 1)
  if waiting > 0:
    result.add $waiting & " command(s) waiting for a file"

proc stopCommandsForPath*(e: Editor, path: string): int =
  ## Kill the external commands running on `path` and report how many.
  ##
  ## Only the file's claim holder may call this; a caller without the claim
  ## would be killing whichever command holds it.
  let key = jobKey(path)
  for running in e.runningBackgroundProcesses:
    if running.path.len > 0 and jobKey(running.path) == key and running.process.isRunning:
      running.process.kill()
      result.inc

proc dropQueuedCommands(e: Editor): int =
  ## Forget every command that has not started and report how many.
  ##
  ## Killing what runs is not enough: the queued commands would take the file
  ## in turn as soon as `:jobs!` empties the process list, and a hook chain
  ## reaches for its next batch when the one in flight ends.
  for _, tickets in e.state.fileJobs.mpairs:
    # Only the waiters, which find their ticket gone on their next poll. Keep
    # the head: the kill is asynchronous, so the holder is still unwinding and
    # an unclaimed path would be taken by the next command to ask for it,
    # running alongside the one still dying on it. The head's own
    # `releaseFileJob` removes it. A waiter that reached the head but has not
    # woken is not a holder; the epoch stops that one.
    result += max(0, tickets.len - 1)
    if tickets.len > 1:
      tickets.setLen(1)

proc stopRunningCommands*(e: Editor): int =
  ## Kill every external command the editor started and drop what is queued
  ## behind them, then report how many were stopped outright. The claims unwind
  ## on their own: the kill lets each awaiting `finally` run.
  ##
  ## Work that stops at its next epoch check instead -- a claim about to be
  ## granted -- is not counted, since it is still running when this returns.
  # Bumped first so everything unwinding below sees it and stops at its next
  # await instead of carrying on into an emptied queue.
  e.state.commandEpoch.inc

  for running in e.runningBackgroundProcesses:
    if running.process.isRunning:
      running.process.kill()
      result.inc
  for qr in e.runningQuickRunProcesses:
    if qr.process.isRunning:
      qr.process.kill()
      result.inc
  result += e.dropQueuedCommands()
