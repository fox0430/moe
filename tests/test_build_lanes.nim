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

## Builds and syntax checks that would trample each other wait their turn, or
## give way to a newer one.
##
## Two builds writing one output at once fail each other's link, and what a
## command writes is not known, so every build waits for the one before it. A
## check only reads, and only the newest save's markers are worth having, so a
## newer check stops the one running on its file.

import std/[unittest, os, strutils, sequtils]

import pkg/chronos

import ../src/moepkg/[editor, config, types, editor_file_jobs, build, job_lanes]
import ../src/moepkg/editor_build_jobs {.all.}
import ../src/moepkg/syntax/tokenizer
import ../src/moepkg/handler

proc testDir(name: string): string =
  result = getTempDir() / ("moe_test_build_lanes_" & name)
  removeDir(result)
  createDir(result)

proc logged(dir: string): string =
  ## The build commands below append a line when they start and when they end.
  let log = dir / "log"
  if fileExists(log):
    readFile(log)
  else:
    ""

proc starts(dir: string): int =
  dir.logged.splitLines.countIt(it.startsWith "start")

proc build(
    e: Editor,
    dir, path: string,
    seconds: string,
    automatic = true,
    root = dir,
    cmd = "",
) =
  ## Submit a build of `path` whose custom command runs in `root` and logs to
  ## `dir`. The command names the file, so builds of two files differ.
  let
    log = dir / "log"
    name = path.extractFilename
    customCmd =
      if cmd.len > 0:
        cmd
      else:
        "sh -c 'echo start " & name & " >> " & log & "; sleep " & seconds & "; echo end " &
          name & " >> " & log & "'"
  e.submitBuild(
    (
      path: path,
      language: 0,
      customCmd: customCmd,
      workspaceRoot: root,
      automatic: automatic,
    )
  )

proc turn() =
  ## Give the loop the turn a lane takes to start what it holds.
  waitFor sleepAsync(1.milliseconds)

proc waitUntil(cond: proc(): bool, limit = 10.seconds): bool =
  let deadline = Moment.now() + limit
  while not cond():
    if Moment.now() > deadline:
      return false
    waitFor sleepAsync(10.milliseconds)
  true

proc waitForStarts(dir: string, count = 1): bool =
  ## Wait until `count` builds are under way, so a stop cannot catch a shell
  ## before it said so.
  waitUntil(
    proc(): bool =
      dir.starts >= count
  )

proc settle(e: Editor): bool =
  ## Wait for every job to end.
  waitUntil(
    proc(): bool =
      toSeq(e.jobLanes.jobs).len == 0,
    20.seconds,
  )

proc queued(e: Editor): seq[string] =
  e.runningCommands().filterIt("(queued)" in it)

suite "Build lanes":
  test "Builds take turns, whatever they build":
    let
      e = newEditor(newEditorConfig())
      dir = testDir("turns")
    e.build(dir, dir / "a.nim", "0.2", root = testDir("turns_a"))
    e.build(dir, dir / "b.nim", "0.2", root = testDir("turns_b"))

    check e.queued ==
      @["Build (queued): " & dir / "a.nim", "Build (queued): " & dir / "b.nim"]
    turn()
    check e.queued == @["Build (queued): " & dir / "b.nim"]
    check e.settle()
    check dir.logged == "start a.nim\nend a.nim\nstart b.nim\nend b.nim\n"

  test "Saves during a build ask for one more, however many":
    let
      e = newEditor(newEditorConfig())
      dir = testDir("collapse")
    e.build(dir, dir / "a.nim", "0.3")
    check dir.waitForStarts()
    for _ in 0 ..< 3:
      e.build(dir, dir / "a.nim", "0.3")

    let listed = e.runningCommands()
    check listed.len == 2
    check "Build (queued): " & dir / "a.nim" in listed
    check e.settle()
    check dir.starts == 2

  test "Saves that come before the build starts run it once":
    let
      e = newEditor(newEditorConfig())
      dir = testDir("collapse_early")
    for _ in 0 ..< 4:
      e.build(dir, dir / "a.nim", "0.1")

    check e.settle()
    check dir.starts == 1

  test "One command asked for by different files runs once more":
    let
      e = newEditor(newEditorConfig())
      dir = testDir("same_command")
      cmd =
        "sh -c 'echo start >> " & dir / "log" & "; sleep 0.3; echo end >> " & dir / "log" &
        "'"
    e.build(dir, dir / "a.nim", "", cmd = cmd)
    check dir.waitForStarts()
    for name in ["b.nim", "c.nim"]:
      e.build(dir, dir / name, "", cmd = cmd)

    check e.queued == @["Build (queued): " & dir / "c.nim"]
    check e.settle()
    check dir.starts == 2

  test "An explicit build is not folded into one on save":
    let
      e = newEditor(newEditorConfig())
      dir = testDir("explicit")
    e.build(dir, dir / "a.nim", "0.2")
    check dir.waitForStarts()
    e.build(dir, dir / "a.nim", "0.1", automatic = false)
    e.build(dir, dir / "a.nim", "0.1")

    check e.queued.len == 2
    check e.settle()
    check dir.starts == 3

  test "A build says when it starts, and that it waits when it has to":
    let
      e = newEditor(newEditorConfig())
      dir = testDir("status")
    e.build(dir, dir / "a.nim", "0.3", automatic = false)
    turn()
    check e.state.statusMessage == "Building: " & dir / "a.nim"

    e.build(dir, dir / "b.nim", "0.1", automatic = false)
    check e.state.statusMessage == "Build queued: " & dir / "b.nim"
    check waitUntil(
      proc(): bool =
        e.state.statusMessage == "Building: " & dir / "b.nim"
    )
    check e.settle()

  test "A build that cannot start says why, and nothing says otherwise":
    let
      e = newEditor(newEditorConfig())
      dir = testDir("no_start")
    e.config.notification.popupNotifications = false
    e.build(dir, dir / "a.nim", "", automatic = false, cmd = dir / "no-such-command")

    check e.settle()
    check "Build error" in e.state.statusMessage
    check "Failed to exec build commands" in e.state.statusMessage

  test "A build that cannot be run says so rather than queueing":
    let
      e = newEditor(newEditorConfig())
      dir = testDir("unknown")
    e.submitBuild(
      (
        path: dir / "a.txt",
        language: langNone.ord,
        customCmd: "",
        workspaceRoot: dir,
        automatic: false,
      )
    )

    check toSeq(e.jobLanes.jobs).len == 0
    check "Build error" in e.state.statusMessage

  test "Stopping ends the running build and forgets the queued one":
    let
      e = newEditor(newEditorConfig())
      dir = testDir("stop")
    e.build(dir, dir / "a.nim", "30")
    e.build(dir, dir / "b.nim", "30")
    check dir.waitForStarts()

    check e.stopRunningCommands() == 2
    check e.settle()
    check dir.starts == 1
    check "end" notin dir.logged
    # What a stopped build printed is not shown as its output.
    check e.windowManager.windows.len == 1

  test "A build stopped before it started never starts":
    let
      e = newEditor(newEditorConfig())
      dir = testDir("stop_early")
    e.build(dir, dir / "a.nim", "30")

    check e.stopRunningCommands() == 1
    check e.settle()
    check dir.starts == 0

  when defined(linux):
    proc escapingBuild(e: Editor, dir, name: string) =
      ## A build that leaves a descendant outside its process group holding its
      ## output, as a build that starts a daemon does.
      let log = dir / "log"
      e.build(
        dir,
        dir / name,
        "",
        cmd =
          "sh -c 'setsid sleep 20 & echo $! > " & dir / "escaped" & "; echo start " &
          name & " >> " & log & "; sleep 30'",
      )

    proc killEscaped(dir: string) =
      let pidFile = dir / "escaped"
      if fileExists(pidFile):
        discard execShellCmd("kill " & readFile(pidFile).strip & " 2>/dev/null")

    test "A stopped build gives the lane up within the grace":
      # Stopped from outside its wait, it waited for the descendant to let go
      # of the pipe, and every build behind it waited too.
      let
        e = newEditor(newEditorConfig())
        dir = testDir("stop_escaped")
      defer:
        killEscaped(dir)
      e.escapingBuild(dir, "a.nim")
      check dir.waitForStarts()

      let stoppedAt = Moment.now()
      check e.stopRunningCommands() == 1
      e.build(dir, dir / "b.nim", "0")
      check dir.waitForStarts(2)
      check Moment.now() - stoppedAt < 6.seconds
      check e.settle()

    test "A build told to stop is listed as stopping and not stopped twice":
      let
        e = newEditor(newEditorConfig())
        dir = testDir("stop_twice")
      defer:
        killEscaped(dir)
      e.escapingBuild(dir, "a.nim")
      check dir.waitForStarts()

      check e.stopRunningCommands() == 1
      check e.runningCommands() == @["Build (stopping): " & dir / "a.nim"]
      check e.stopRunningCommands() == 0
      check e.settle()

  test "Quitting stops the running build and starts nothing queued":
    let
      e = newEditor(newEditorConfig())
      dir = testDir("quit")
    e.build(dir, dir / "a.nim", "30")
    e.build(dir, dir / "b.nim", "30")
    check dir.waitForStarts()

    e.cleanupBackgroundProcesses()
    check e.settle()
    check dir.starts == 1
    check "end" notin dir.logged

  test "What counts as the same build":
    let root = getTempDir() / "moe_test_build_lanes_keys"
    proc collapse(
        path: string,
        customCmd = "",
        workspaceRoot = root,
        automatic = true,
        language = langNim,
    ): string =
      let info: BuildInfo = (
        path: path,
        language: language.ord,
        customCmd: customCmd,
        workspaceRoot: workspaceRoot,
        automatic: automatic,
      )
      buildCollapse(
        info, buildOnSaveCommand(path, language, customCmd, workspaceRoot).get
      )

    # A custom command does the same work whichever file asked for it.
    check collapse(root / "a.nim", "nimble build") ==
      collapse(root / "b.nim", "nimble build")
    check collapse(root / "a.nim", "nimble build") ==
      collapse(root / "a.nim", "nimble build", root / "." / "")
    check collapse(root / "a.nim", "nimble build") !=
      collapse(root / "a.nim", "nimble test")
    check collapse(root / "a.nim", "nimble build") !=
      collapse(root / "a.nim", "nimble build", root / "sub")
    # The default command names the file for Nim, not for Rust.
    check collapse(root / "a.nim") != collapse(root / "b.nim")
    check collapse(root / "main.rs", language = langRust) ==
      collapse(root / "lib.rs", language = langRust)
    check collapse(root / "a.nim", automatic = false) != collapse(root / "a.nim")

suite "Syntax check lanes":
  proc check(e: Editor, path: string) =
    e.submitSyntaxCheck((path: path, language: langNim.ord))

  proc states(e: Editor): seq[JobState] =
    for job in e.jobLanes.jobs:
      result.add job.state

  test "Saves of one file that come before the check starts check it once":
    let
      e = newEditor(newEditorConfig())
      dir = testDir("check_burst")
      path = dir / "a.nim"
    writeFile(path, "echo 1\n")
    for _ in 0 ..< 3:
      e.check(path)

    check e.states == @[jsWaiting]
    check e.settle()
    check e.state.syntaxCheckResults.path == path

  test "A newer check stops the one running on the same file":
    let
      e = newEditor(newEditorConfig())
      dir = testDir("check")
      path = dir / "a.nim"
    writeFile(path, "echo 1\n")
    e.check(path)
    turn()
    check e.states == @[jsRunning]

    e.check(path)
    check e.states == @[jsStopping, jsWaiting]
    check e.settle()
    check e.state.syntaxCheckResults.path == path

  test "Checks of different files run side by side":
    let
      e = newEditor(newEditorConfig())
      dir = testDir("check_apart")
    writeFile(dir / "a.nim", "echo 1\n")
    writeFile(dir / "b.nim", "echo 1\n")
    e.check(dir / "a.nim")
    e.check(dir / "b.nim")
    turn()

    check e.states == @[jsRunning, jsRunning]
    check e.settle()

  test "A stopped check reports nothing":
    let
      e = newEditor(newEditorConfig())
      dir = testDir("check_stop")
      path = dir / "a.nim"
    writeFile(path, "echo (\n")
    e.check(path)
    turn()
    e.state.statusMessage = ""

    check e.stopRunningCommands() == 1
    check e.settle()
    check e.state.syntaxCheckResults.path == ""
    check e.state.statusMessage == ""
