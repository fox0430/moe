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

## Tests for editor_file_jobs.nim: the per-file claim that keeps hooks, builds
## and syntax checks from overlapping on one path.
import std/[unittest, os, sequtils, tables]

import pkg/chronos

import ../src/moepkg/[editor, config, editor_file_jobs]
import ../src/moepkg/types/editor_types

proc testEditor(): Editor =
  newEditor(newEditorConfig())

suite "editor_file_jobs":
  test "A free path is claimed without waiting":
    let e = testEditor()
    let path = getTempDir() / "moe_test_job_free.nim"
    let claim = waitFor e.claimFileJob(path)
    check claim.key.len > 0
    check e.state.fileJobs.len == 1
    e.releaseFileJob(claim)
    check e.state.fileJobs.len == 0

  test "An empty path claims nothing":
    let e = testEditor()
    let claim = waitFor e.claimFileJob("")
    check claim.key.len == 0
    check e.state.fileJobs.len == 0
    # Releasing it is a no-op rather than an error.
    e.releaseFileJob(claim)

  test "A second claim waits for the first to be released":
    let e = testEditor()
    let path = getTempDir() / "moe_test_job_wait.nim"
    let first = waitFor e.claimFileJob(path)

    # Started, not awaited: it has to stay pending while the first claim holds.
    let second = e.claimFileJob(path)
    waitFor sleepAsync(40.milliseconds)
    check not second.finished

    e.releaseFileJob(first)
    let claim = waitFor second
    check claim.key.len > 0
    e.releaseFileJob(claim)
    check e.state.fileJobs.len == 0

  test "Two spellings of one file are the same claim":
    let e = testEditor()
    let dir = getTempDir() / "moe_test_job_spelling"
    createDir(dir)
    defer:
      removeDir(dir)
    let held = waitFor e.claimFileJob(dir / "a.nim")

    let other = e.claimFileJob(dir / "." / "a.nim")
    waitFor sleepAsync(40.milliseconds)
    check not other.finished

    e.releaseFileJob(held)
    e.releaseFileJob(waitFor other)
    check e.state.fileJobs.len == 0

  test "Claims on different files do not wait for each other":
    let e = testEditor()
    let dir = getTempDir() / "moe_test_job_distinct"
    createDir(dir)
    defer:
      removeDir(dir)
    let held = waitFor e.claimFileJob(dir / "a.nim")
    let other = waitFor e.claimFileJob(dir / "b.nim")
    check @[held, other].allIt(it.key.len > 0)
    check e.state.fileJobs.len == 2
    e.releaseFileJob(held)
    e.releaseFileJob(other)
    check e.state.fileJobs.len == 0

  test "The file is handed on in the order it was asked for":
    let e = testEditor()
    let path = getTempDir() / "moe_test_job_order.nim"
    let held = waitFor e.claimFileJob(path)

    # Started in order; without a queue the poll timing would decide the order.
    let order = new seq[int]
    proc waiter(
        e: Editor, path: string, id: int, order: ref seq[int]
    ): Future[void] {.async.} =
      let claim = await e.claimFileJob(path)
      order[].add id
      e.releaseFileJob(claim)

    let
      first = e.waiter(path, 1, order)
      second = e.waiter(path, 2, order)
      third = e.waiter(path, 3, order)
    waitFor sleepAsync(40.milliseconds)
    check order[].len == 0

    e.releaseFileJob(held)
    waitFor first
    waitFor second
    waitFor third

    check order[] == @[1, 2, 3]
    check e.state.fileJobs.len == 0

  test "A granted claim says so, and a waiter dropped by :jobs! does not":
    let e = testEditor()
    let path = getTempDir() / "moe_test_job_dropped.nim"
    let held = waitFor e.claimFileJob(path)
    check held.granted

    let waiting = e.claimFileJob(path)
    waitFor sleepAsync(40.milliseconds)
    check not waiting.finished

    # `:jobs!` drops the queue, so the waiter gives up instead of taking the
    # file later.
    discard e.stopRunningCommands()
    let claim = waitFor waiting
    check not claim.granted
    check claim.key.len == 0

  test ":jobs! leaves the path claimed by the command still unwinding on it":
    # The kill is asynchronous, so the holder is still on the file; dropping
    # its ticket would let the next command run alongside it.
    let e = testEditor()
    let path = getTempDir() / "moe_test_job_holder.nim"
    let held = waitFor e.claimFileJob(path)
    check held.granted

    discard e.stopRunningCommands()
    check e.state.fileJobs.len == 1

    let next = e.claimFileJob(path)
    waitFor sleepAsync(40.milliseconds)
    check not next.finished

    # Once the holder does let go, the path is free again.
    e.releaseFileJob(held)
    let claim = waitFor next
    check claim.granted
    e.releaseFileJob(claim)
    check e.state.fileJobs.len == 0

  test ":jobs! refuses a claim that has reached the head of the queue":
    # `:jobs!` leaves the queue head for the command still unwinding, but a
    # waiter that reached the head without waking has started nothing yet and
    # must not be granted.
    let e = testEditor()
    let path = getTempDir() / "moe_test_job_head_waiter.nim"
    let held = waitFor e.claimFileJob(path)

    let waiting = e.claimFileJob(path, nil, e.commandEpoch)
    waitFor sleepAsync(40.milliseconds)
    check not waiting.finished

    # Released and stopped without turning the loop, so the waiter is still
    # asleep at the head when the stop lands.
    e.releaseFileJob(held)
    discard e.stopRunningCommands()

    let claim = waitFor waiting
    check not claim.granted
    check e.state.fileJobs.len == 0

  test "A claim taken without an epoch survives :jobs!":
    # A deferred write claims without an epoch, so `:jobs!` does not stop it.
    let e = testEditor()
    let path = getTempDir() / "moe_test_job_no_epoch.nim"
    let held = waitFor e.claimFileJob(path)

    let waiting = e.claimFileJob(path, nil, NoCommandEpoch)
    waitFor sleepAsync(40.milliseconds)

    e.releaseFileJob(held)
    discard e.stopRunningCommands()

    let claim = waitFor waiting
    check claim.granted
    e.releaseFileJob(claim)

  test "An empty path is granted without being queued":
    let e = testEditor()
    let claim = waitFor e.claimFileJob("")
    check claim.granted
    check claim.key.len == 0

  test "A waiter that gives up leaves the queue without taking its turn":
    # What Escape does to a write filter queued behind another command: without
    # giveUp it would ignore the user until FileJobMaxWaitSeconds runs out.
    let e = testEditor()
    let path = getTempDir() / "moe_test_job_giveup.nim"
    let held = waitFor e.claimFileJob(path)

    var abandoned = false
    let giveUp: FileJobGiveUp = proc(): bool {.gcsafe, raises: [].} =
      abandoned

    let waiting = e.claimFileJob(path, giveUp)
    waitFor sleepAsync(40.milliseconds)
    check not waiting.finished

    abandoned = true
    let claim = waitFor waiting
    check not claim.granted
    check claim.key.len == 0
    # The ticket is gone with it, so the holder is the only one left.
    check e.state.fileJobs[held.key].len == 1

    e.releaseFileJob(held)
    check e.state.fileJobs.len == 0

  test "A waiter that has already given up never queues":
    let e = testEditor()
    let path = getTempDir() / "moe_test_job_giveup_early.nim"
    let giveUp: FileJobGiveUp = proc(): bool {.gcsafe, raises: [].} =
      true

    let claim = waitFor e.claimFileJob(path, giveUp)
    check not claim.granted
    check e.state.fileJobs.len == 0
