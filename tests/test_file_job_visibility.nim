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

## Seeing and ending the external commands that hold a file.
##
## A command holds its file until it exits, and one with `timeout = 0` may hold
## it for the rest of the session. `:jobs` reports it and `:jobs!` ends it.

import std/[unittest, os, strutils, tables]

import pkg/chronos

import ../src/moepkg/[editor, config, types, background_process, editor_file_jobs]
import ../src/moepkg/handler {.all.}

proc startSleeper(e: Editor, label, path: string): BackgroundProcess =
  proc go(): Future[StartProcessResult] {.async.} =
    await startBackgroundProcess(
      BackgroundProcessCommand(cmd: "sleep", args: @["30"], workingDir: getTempDir())
    )

  let started = waitFor go()
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

  test "The wait notice names what is holding the file":
    let e = newEditor(newEditorConfig())
    let p = e.startSleeper("BufWritePre hook (nimpretty)", "/src/a.nim")
    defer:
      p.kill()

    let notice = e.waitNotice("/src/a.nim")
    check "BufWritePre hook (nimpretty)" in notice
    check "/src/a.nim" in notice
    # Named, so a stuck wait has somewhere to go.
    check ":jobs" in notice

  test "The wait notice matches on the file, not on how it was spelled":
    let e = newEditor(newEditorConfig())
    let p = e.startSleeper("Build", absolutePath("a.nim"))
    defer:
      p.kill()

    check "Build" in e.waitNotice("./a.nim")

  test "A file nothing named still gets an answer":
    let e = newEditor(newEditorConfig())
    check "Another command" in e.waitNotice("/src/a.nim")
