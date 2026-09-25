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

## Seeing and ending the external commands the editor has started.
##
## A long-running command gives no sign of itself on the screen. `:jobs`
## reports it and `:jobs!` ends it.

import std/[unittest, os, strutils]

import pkg/results

import ../src/moepkg/[editor, config, background_process, editor_file_jobs]
import ../src/moepkg/handler {.all.}

proc startSleeper(e: Editor, label, path: string): BackgroundProcess =
  let started = startBackgroundProcess(
    BackgroundProcessCommand(cmd: "sleep", args: @["30"], workingDir: getTempDir())
  )
  doAssert started.isOk
  result = started.get
  e.addRunningProcess(result, label, path)

suite "File jobs - visibility":
  test "Nothing running lists nothing":
    let e = newEditor(newEditorConfig())
    check e.runningCommands().len == 0

  test "A running command is listed with what it is and the file it holds":
    let e = newEditor(newEditorConfig())
    let p = e.startSleeper("BufWritePre hook (nimpretty)", "/src/a.nim")
    defer:
      p.kill()

    let listed = e.runningCommands()
    check listed.len == 1
    check "BufWritePre hook (nimpretty)" in listed[0]
    check "/src/a.nim" in listed[0]
    # Elapsed, so an endless wait reads as one.
    check "s" in listed[0]

  test "Stopping ends every running command and reports the count":
    let e = newEditor(newEditorConfig())
    discard e.startSleeper("Build", "/src/a.nim")
    discard e.startSleeper("Syntax check", "/src/b.nim")

    check e.stopRunningCommands() == 2

  test "Stopping with nothing running reports nothing":
    let e = newEditor(newEditorConfig())
    check e.stopRunningCommands() == 0

when defined(linux):
  import std/posix

  import pkg/chronos

  import ../src/moepkg/child_process

  proc leaveSleeper(e: Editor, pidFile: string): (BackgroundProcess, Pid) =
    ## A command that exits at once and leaves a sleeper in its group holding
    ## its output open, as `sh -c 'server &'` does.
    removeFile(pidFile)
    let started = startBackgroundProcess(
      BackgroundProcessCommand(
        cmd: "sh",
        args: @["-c", "sleep 30 & echo $! > " & pidFile],
        workingDir: getTempDir(),
      )
    )
    doAssert started.isOk
    let bp = started.get
    e.addRunningProcess(bp, "Build", "/src/a.nim")
    for _ in 0 ..< 500:
      if fileExists(pidFile) and readFile(pidFile).strip.len > 0:
        break
      sleep(10)
    for _ in 0 ..< 500:
      if not bp.process.running():
        break
      sleep(10)
    doAssert not bp.process.running()
    (bp, Pid(parseInt(readFile(pidFile).strip)))

  proc gone(pid: Pid): bool =
    ## Whether `pid` has died; it is not ours, so init reaps it.
    for _ in 0 ..< 200:
      if posix.kill(pid, 0) != 0:
        return true
      try:
        if readFile("/proc/" & $pid & "/stat").split(' ')[2] == "Z":
          return true
      except IOError:
        return true
      sleep(10)
    false

  suite "File jobs - what an exited command left running":
    test "Stopping reaches it":
      let
        e = newEditor(newEditorConfig())
        pidFile = getTempDir() / "moe_test_jobs_stop_leftover"
        (bp, sleeper) = e.leaveSleeper(pidFile)
      defer:
        # Unreaped, the command's pid still names the group: this reaches the
        # sleeper should the check below fail, and nobody else.
        bp.kill()
        waitFor bp.closeAsync()
        removeFile(pidFile)

      check e.runningCommands().len == 1
      check e.stopRunningCommands() == 1
      check gone(sleeper)

    test "Quitting reaches it":
      let
        e = newEditor(newEditorConfig())
        pidFile = getTempDir() / "moe_test_jobs_quit_leftover"
        (bp, sleeper) = e.leaveSleeper(pidFile)
      defer:
        # Unreaped, the command's pid still names the group: this reaches the
        # sleeper should the check below fail, and nobody else.
        bp.kill()
        waitFor bp.closeAsync()
        removeFile(pidFile)

      e.cleanupBackgroundProcesses()
      check gone(sleeper)
