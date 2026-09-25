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

## End-to-end tests for user hooks: from an event through the file's lane to
## the command's effect on disk and on the buffer.

import std/[unittest, options, os, sequtils, strutils, json]

import pkg/chronos

import
  ../src/moepkg/[
    buffer, types, editor, config, hooks, editor_file, editor_file_jobs, editor_reload,
    editor_window, window_manager, job_lanes, message_log,
  ]
import ../src/moepkg/editor_hooks {.all.}
import ../src/moepkg/syntax/tokenizer
import ../src/moepkg/handler {.all.}
import
  ../src/moepkg/command_handlers/[handler_result, editor_ops, viewer_ops, backup_ops]

proc testDir(name: string): string =
  ## A directory of this run's own. The pid is in the name because the suite
  ## can be running in more than one process at once, and a fixed name would
  ## have each `removeDir` below pull the ground out from under the others.
  result = getTempDir() / ("moe_test_hook_run_" & $getCurrentProcessId() & "_" & name)
  removeDir(result)
  createDir(result)

proc hookJobs(e: Editor): seq[JobInfo] =
  ## The hook jobs not ended, in the order `:jobs` lists them.
  for job in e.jobLanes.jobs:
    if " hook" in job.label:
      result.add job

proc turn() =
  ## Give a lane the turn it takes to start what was submitted.
  waitFor sleepAsync(20.milliseconds)

proc drain(e: Editor, until: proc(): bool) =
  ## Keep the event loop turning until the hooks have had their effect. A lane
  ## starts its job on a later turn and hands back no end to await, hence the
  ## predicate. The pending queue runs too, for other work a test queues.
  waitFor e.handlePendingAsyncOperations(FrontendHooks())
  for _ in 0 ..< 400:
    if until():
      break
    waitFor sleepAsync(10.milliseconds)
  # One more turn so the job ends even once the effect is visible.
  turn()

proc openInEditor(e: Editor, path: string, content: string) =
  ## Open a real file the way the editor does, so the buffer carries the path,
  ## language and modified state the hooks read.
  writeFile(path, content)
  discard e.loadFile(path)
  # loadFile queues BufReadPost hooks; tests that care queue their own event.
  discard e.jobLanes.stopAll()

suite "Hooks - running":
  test "A matching hook runs its command":
    let dir = testDir("basic")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost, command: "sh -c 'echo ran > ${dir}/out.txt'", timeout: 5
      )
    ]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    check editor.hookJobs.len == 1
    editor.drain(
      proc(): bool =
        fileExists(dir / "out.txt")
    )

    check fileExists(dir / "out.txt")
    check readFile(dir / "out.txt").strip == "ran"
    check editor.hookJobs.len == 0

  test "A non-matching hook does not run":
    let dir = testDir("nomatch")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        filetype: @["go"],
        command: "sh -c 'echo ran > ${dir}/out.txt'",
        timeout: 5,
      )
    ]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    check editor.hookJobs.len == 0
    editor.drain(
      proc(): bool =
        true
    )

    check not fileExists(dir / "out.txt")

  test "The command runs in the file's directory by default":
    let dir = testDir("cwd")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries =
      @[HookEntry(event: heBufWritePost, command: "sh -c 'pwd > cwd.txt'", timeout: 5)]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        fileExists(dir / "cwd.txt")
    )

    check fileExists(dir / "cwd.txt")
    check readFile(dir / "cwd.txt").strip == dir

  test "A relative workingDir is taken from the file's directory":
    let dir = testDir("relcwd")
    defer:
      removeDir(dir)
    createDir(dir / "sub")
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command: "sh -c 'pwd > cwd.txt'",
        workingDir: "sub",
        timeout: 5,
      )
    ]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        fileExists(dir / "sub" / "cwd.txt")
    )

    check readFile(dir / "sub" / "cwd.txt").strip == dir / "sub"

  test "Every matching hook runs, in config order":
    let dir = testDir("multi")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    # The slow entry comes first: the entries share a file, so they have to run
    # one after the other, not merely start in order.
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command: "sh -c 'sleep 0.3; echo one >> ${dir}/log'",
        timeout: 5,
      ),
      HookEntry(
        event: heBufWritePost, command: "sh -c 'echo two >> ${dir}/log'", timeout: 5
      ),
    ]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    # One job holding both entries, so nothing can interleave them.
    check editor.hookJobs.len == 1
    check editor.hookJobs[0].label == "BufWritePost hooks (sh, sh)"
    editor.drain(
      proc(): bool =
        fileExists(dir / "log") and readFile(dir / "log").count('\n') >= 2
    )

    check readFile(dir / "log").splitLines.filterIt(it.len > 0) == @["one", "two"]

  test "A successful hook says nothing":
    let dir = testDir("silent")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost, command: "sh -c 'echo x > ${dir}/done'", timeout: 5
      )
    ]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        fileExists(dir / "done")
    )

    check editor.state.statusMessage.len == 0

  test "A non-zero exit is reported with the command's last line":
    let dir = testDir("failure")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost, command: "sh -c 'echo bad syntax; exit 3'", timeout: 5
      )
    ]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        editor.state.statusMessage.len > 0
    )

    check editor.state.statusMessage.contains("exited with 3")
    check editor.state.statusMessage.contains("bad syntax")

  test "A failure quotes at most a status line's worth of the last line":
    # A minified JSON error is a single line of any length.
    let dir = testDir("longline")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command: "sh -c 'printf \"%05000d\\n\" 0; exit 1'",
        timeout: 5,
      )
    ]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        "exited with 1" in editor.state.statusMessage
    )
    check "exited with 1: 000" in editor.state.statusMessage
    check editor.state.statusMessage.endsWith("...")
    check editor.state.statusMessage.len < 400

  test "A failure does not quote the mark of dropped output":
    # All the kept tail is blank: there is nothing of the command's to quote.
    let dir = testDir("dropmark")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        # One long line, then more than the limit of blank ones. Not `yes`:
        # its broken pipe on stderr would be the last line.
        command:
          "sh -c 'head -c 2000000 /dev/zero | tr \"\\\\0\" x; " &
          "head -c 1200000 /dev/zero | tr \"\\\\0\" \"\\\\n\"; exit 1'",
        timeout: 10,
      )
    ]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        "exited with 1" in editor.state.statusMessage
    )
    check editor.state.statusMessage.endsWith("exited with 1")

  test "A command that does not exist is reported":
    let dir = testDir("missing")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries =
      @[HookEntry(event: heBufWritePost, command: "moe-no-such-command", timeout: 5)]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        editor.state.statusMessage.len > 0
    )

    # No shell starts it, so the start itself fails and says why.
    check "moe-no-such-command" in editor.state.statusMessage
    check "No such file or directory" in editor.state.statusMessage

  test "The command's directory is its own, not moe's":
    # moe's working directory is shared by every thread; a hook must not move
    # it, even for a command that fails to start.
    let dir = testDir("ownwd")
    defer:
      removeDir(dir)
    let before = getCurrentDir()
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries = @[
      HookEntry(event: heBufWritePost, command: "moe-no-such-command", timeout: 5),
      HookEntry(event: heBufWritePost, command: "sh -c 'pwd > ${dir}/pwd'", timeout: 5),
    ]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    # Watched while the batch runs, not only after it.
    var moved = false
    for _ in 0 ..< 200:
      waitFor editor.handlePendingAsyncOperations(FrontendHooks())
      if getCurrentDir() != before:
        moved = true
      if fileExists(dir / "pwd"):
        break
      waitFor sleepAsync(5.milliseconds)

    check not moved
    check fileExists(dir / "pwd") and readFile(dir / "pwd").strip == dir

  test "The shell example in the docs keeps a file name out of the script":
    # Placeholders handed to `sh -c` as arguments, never written into it.
    let dir = testDir("shellargs")
    defer:
      removeDir(dir)
    let path = dir / "a';touch pwned;'.nim"
    writeFile(path, "TODO\n")
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command: "sh -c 'grep -c TODO \"$1\" > \"$2\"/todo.count' sh ${file} ${dir}",
        timeout: 5,
      )
    ]

    editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        fileExists(dir / "todo.count")
    )
    check fileExists(dir / "todo.count") and readFile(dir / "todo.count").strip == "1"
    check not fileExists(dir / "pwned")
    check not fileExists(getCurrentDir() / "pwned")

  test "A command that never exits is killed at the timeout":
    let dir = testDir("timeout")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries =
      @[HookEntry(event: heBufWritePost, command: "sleep 30", timeout: 1)]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        editor.state.statusMessage.len > 0
    )

    check editor.state.statusMessage.contains("Timed out")
    editor.drain(
      proc(): bool =
        editor.hookJobs.len == 0
    )
    check editor.hookJobs.len == 0

  test "A relative file path is absolutized before the command sees it":
    let dir = testDir("relative")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries =
      @[HookEntry(event: heBufWritePost, command: "true ${file}", timeout: 5)]

    let previousDir = getCurrentDir()
    setCurrentDir(dir)
    # Read the directory back: it may have been reached through a symlink.
    let cwd = getCurrentDir()
    let hooks = editor.hookCommands(heBufWritePost, "a.nim", SourceLanguage.langNim)
    setCurrentDir(previousDir)

    check hooks.len == 1
    # ${file} and the default working directory have to agree: the command runs
    # in the file's own directory, so a bare "a.nim" would resolve one level
    # deeper than the file actually is.
    check hooks[0].args == @[cwd / "a.nim"]
    check hooks[0].workingDir == cwd
    check hooks[0].path == cwd / "a.nim"

  test "showOutput shows the output of a command that exits non-zero":
    let dir = testDir("showoutput")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    let bufferCount = editor.buffers.len
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command: "sh -c 'echo lint complaint; exit 1'",
        showOutput: true,
        timeout: 5,
      )
    ]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        editor.buffers.len > bufferCount
    )

    # A linter exits non-zero exactly when it has something to report, which is
    # when its output is wanted most.
    check editor.buffers.len == bufferCount + 1
    check editor.buffers[^1].getLine(0) == "lint complaint"
    check editor.state.statusMessage.contains("exited with 1")

  test "showOutput keeps the focus and the mode the user was in":
    # A hook fires on its own, unlike QuickRun or a build. Taking the window
    # and forcing Normal mode would turn whatever the user typed while the
    # command ran into Normal-mode commands.
    let dir = testDir("showoutputfocus")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(dir / "a.nim", "x\n")
    let
      windowCount = editor.windowManager.windows.len
      bufferCount = editor.buffers.len
      editedBuffer = editor.activeBuffer
    editor.setMode(EditorMode.Insert)
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command: "sh -c 'echo complaint'",
        showOutput: true,
        timeout: 5,
      )
    ]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        editor.buffers.len > bufferCount
    )

    check editor.windowManager.windows.len == windowCount + 1
    check editor.state.mode == EditorMode.Insert
    check editor.activeBuffer == editedBuffer

  test "A second firing replaces the output instead of splitting again":
    let dir = testDir("showoutputreuse")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(dir / "a.nim", "x\n")
    let
      windowCount = editor.windowManager.windows.len
      bufferCount = editor.buffers.len
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command: "sh -c 'echo first'",
        showOutput: true,
        timeout: 5,
      )
    ]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        editor.buffers.len > bufferCount
    )
    check editor.windowManager.windows.len == windowCount + 1
    check editor.buffers.len == bufferCount + 1

    # A BufWritePost hook with showOutput would otherwise grow the window tree
    # by one per save.
    editor.config.hooks.entries[0].command = "sh -c 'echo second'"
    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        let idx = editor.bufferIndexById(editor.state.commandOutputBufferId)
        idx >= 0 and editor.buffers[idx].getLine(0) == "second"
    )

    check editor.windowManager.windows.len == windowCount + 1
    check editor.buffers.len == bufferCount + 1
    let outIdx = editor.bufferIndexById(editor.state.commandOutputBufferId)
    check outIdx >= 0
    check editor.buffers[outIdx].getLine(0) == "second"

  test "The entries one event matches add their output to one window":
    # Each replacing the one before would leave a linter's findings in view
    # only until the formatter after it printed a line.
    let dir = testDir("showoutputjob")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(dir / "a.nim", "x\n")
    let windowCount = editor.windowManager.windows.len
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command: "sh -c 'echo finding-1; echo finding-2; exit 1'",
        showOutput: true,
        timeout: 5,
      ),
      HookEntry(
        event: heBufWritePost, command: "echo formatted", showOutput: true, timeout: 5
      ),
    ]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        editor.hookJobs.len == 0
    )

    check editor.windowManager.windows.len == windowCount + 1
    let outIdx = editor.bufferIndexById(editor.state.commandOutputBufferId)
    check outIdx >= 0
    check toSeq(editor.buffers[outIdx].lines) ==
      @[
        "==> sh -c 'echo finding-1; echo finding-2; exit 1' <==", "finding-1",
        "finding-2", "", "==> echo formatted <==", "formatted",
      ]

  test "Output is not headed when only one of the entries shows it":
    let dir = testDir("showoutputonehead")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(dir / "a.nim", "x\n")
    editor.config.hooks.entries = @[
      HookEntry(event: heBufWritePost, command: "echo hidden", timeout: 5),
      HookEntry(
        event: heBufWritePost, command: "echo shown", showOutput: true, timeout: 5
      ),
    ]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        editor.hookJobs.len == 0
    )

    let outIdx = editor.bufferIndexById(editor.state.commandOutputBufferId)
    check outIdx >= 0
    check toSeq(editor.buffers[outIdx].lines) == @["shown"]

  test "Closing the output window does not strand its buffer":
    # Closing a window leaves its buffer in `e.buffers`, so without an explicit
    # removal every close-then-fire cycle would add one more read-only buffer
    # to the buffer list and the tab line.
    let dir = testDir("showoutputclosed")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(dir / "a.nim", "x\n")
    let
      windowCount = editor.windowManager.windows.len
      bufferCount = editor.buffers.len
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command: "sh -c 'echo first'",
        showOutput: true,
        timeout: 5,
      )
    ]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        editor.buffers.len > bufferCount
    )
    check editor.windowManager.windows.len == windowCount + 1

    for i, window in editor.windowManager.windows:
      if window.buffer.id == editor.state.commandOutputBufferId:
        editor.windowManager.activateWindow(i)
        discard editor.closeWindow()
        break
    editor.syncActiveWindow()
    check editor.windowManager.windows.len == windowCount

    editor.config.hooks.entries[0].command = "sh -c 'echo second'"
    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        let idx = editor.bufferIndexById(editor.state.commandOutputBufferId)
        idx >= 0 and editor.buffers[idx].getLine(0) == "second"
    )

    check editor.windowManager.windows.len == windowCount + 1
    check editor.buffers.len == bufferCount + 1

  test "showOutput hands the previous mode back to the user's window":
    # `state.activeWindow` is a cached ref refreshed by `syncActiveWindow`, so
    # writing `previousMode` before the sync would land it on the freshly
    # created output window instead.
    let dir = testDir("showoutputprevmode")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(dir / "a.nim", "x\n")
    let editedBuffer = editor.activeBuffer
    editor.setMode(EditorMode.Insert)
    editor.state.previousMode = EditorMode.Visual
    let bufferCount = editor.buffers.len
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command: "sh -c 'echo complaint'",
        showOutput: true,
        timeout: 5,
      )
    ]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        editor.buffers.len > bufferCount
    )

    check editor.activeBuffer == editedBuffer
    check editor.state.previousMode == EditorMode.Visual
    for window in editor.windowManager.windows:
      if window.buffer.id == editor.state.commandOutputBufferId:
        check window.previousMode == EditorMode.Normal

  test "A command reads /dev/null, not the terminal":
    # In its own process group, reading the terminal would stop it (SIGTTIN)
    # until its timeout.
    let dir = testDir("stdin")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command: "sh -c 'readlink /proc/self/fd/0 > ${dir}/stdin'",
        timeout: 5,
      )
    ]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        fileExists(dir / "stdin") and readFile(dir / "stdin").len > 0
    )
    check fileExists(dir / "stdin") and readFile(dir / "stdin").strip == "/dev/null"

suite "Hooks - BufWritePost firing":
  test ":w queues the write hooks":
    let dir = testDir("write")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    editor.config.hooks.entries =
      @[HookEntry(event: heBufWritePost, command: "true", timeout: 5)]

    editor.processSaveResult(
      HandlerResult(kind: hrSave, saveFilename: none(string), forceSave: false),
      editor.activeBuffer,
    )

    check editor.hookJobs.len == 1
    check editor.hookJobs[0].path == path

  test ":wa queues the write hooks for every buffer it wrote":
    let dir = testDir("writeall")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(dir / "a.nim", "x\n")
    editor.config.hooks.entries =
      @[HookEntry(event: heBufWritePost, command: "true", timeout: 5)]
    check editor.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "y").isOk

    editor.processSaveAllResult(HandlerResult(kind: hrSaveAll, forceSaveAll: false))

    check editor.hookJobs.len == 1
    check editor.hookJobs[0].path == dir / "a.nim"

  test "Auto save keeps quiet unless onAutoSave is set":
    let dir = testDir("autosave")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(dir / "a.nim", "x\n")
    editor.config.autoSave.enable = true
    editor.config.autoSave.interval = 0
    editor.config.hooks.entries =
      @[HookEntry(event: heBufWritePost, command: "true", timeout: 5)]
    check editor.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "y").isOk

    editor.autoSave()
    check editor.hookJobs.len == 0

    check editor.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "z").isOk
    editor.config.hooks.onAutoSave = true
    editor.autoSave()
    check editor.hookJobs.len == 1

  test ":w to a new extension matches hooks by the saved path":
    let dir = testDir("saveas")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(dir / "a.py", "x\n")
    editor.config.hooks.entries = @[
      HookEntry(event: heBufWritePost, command: "true", filetype: @["nim"], timeout: 5)
    ]

    editor.processSaveResult(
      HandlerResult(kind: hrSave, saveFilename: some(dir / "b.nim"), forceSave: false),
      editor.activeBuffer,
    )

    check editor.hookJobs.len == 1
    check editor.hookJobs[0].path == dir / "b.nim"

  test ":w to a new extension no longer matches the old filetype":
    let dir = testDir("saveasold")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(dir / "a.py", "x\n")
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost, command: "true", filetype: @["python"], timeout: 5
      )
    ]

    editor.processSaveResult(
      HandlerResult(kind: hrSave, saveFilename: some(dir / "b.nim"), forceSave: false),
      editor.activeBuffer,
    )

    check editor.hookJobs.len == 0

  test "Two buffers on the same file fire its hooks once":
    let dir = testDir("samepath")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    # `${filetype}` tells the buffers' firings apart, so a second one would be
    # a job of its own instead of taking the first one's place.
    editor.config.hooks.entries =
      @[HookEntry(event: heBufWritePost, command: "true ${filetype}", timeout: 5)]

    let second = newTextBuffer("x\n")
    second.filePath = some(path)
    second.language = SourceLanguage.langNone
    editor.addBuffer(second)
    check editor.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "y").isOk
    check second.insertText(BufferPosition(line: 0, column: 0), "z").isOk

    # `:wa!` writes the file once, by one buffer, so the hooks are owed once:
    # two runs of the same formatter would overwrite each other.
    editor.processSaveAllResult(HandlerResult(kind: hrSaveAll, forceSaveAll: true))
    check editor.hookJobs.len == 1

suite "Hooks - BufReadPost":
  test "Opening a file queues the read hooks":
    let dir = testDir("bufread")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    writeFile(path, "x\n")
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufReadPost, command: "sh -c 'echo read > ${dir}/out.txt'", timeout: 5
      )
    ]

    check editor.loadFile(path).isOk
    check editor.hookJobs.len == 1
    editor.drain(
      proc(): bool =
        fileExists(dir / "out.txt")
    )

    check readFile(dir / "out.txt").strip == "read"

  test "A file that does not exist yet fires nothing":
    # `:e newfile.nim` builds a buffer for a path that was never read, so a
    # formatter attached to BufReadPost would fail on every new file.
    let dir = testDir("bufread_new")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries =
      @[HookEntry(event: heBufReadPost, command: "true", timeout: 5)]

    check editor.editFile(dir / "new.nim").isOk
    check editor.hookJobs.len == 0

  test "A write hook does not fire on a read":
    let dir = testDir("bufread_write")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    writeFile(path, "x\n")
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries =
      @[HookEntry(event: heBufWritePost, command: "true", timeout: 5)]

    check editor.loadFile(path).isOk
    check editor.hookJobs.len == 0

suite "Hooks - one file at a time":
  test "Repeated writes while a hook runs collapse to one more run":
    # A run already in flight may have read the file before the newest write
    # landed, so exactly one job is kept behind it -- and no more, however long
    # `:w` is held down.
    let dir = testDir("serial_writes")
    defer:
      removeDir(dir)
    let
      path = dir / "a.nim"
      log = dir / "log.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command: "sh -c 'sleep 0.2; echo run >> " & log & "'",
        timeout: 5,
      )
    ]

    # The first write, running.
    editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
    turn()
    check editor.hookJobs.mapIt(it.state) == @[jsRunning]

    # `:w` held down behind it: the first firing is kept, since the run in
    # flight may predate it, and the rest are collapsed into that one.
    for _ in 0 ..< 5:
      editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
    check editor.hookJobs.mapIt(it.state) == @[jsRunning, jsWaiting]

    editor.drain(
      proc(): bool =
        false
    )

    check readFile(log).splitLines.filterIt(it.len > 0).len == 2

  test "Alternating events while a hook runs keep the queue bounded":
    # One job of each event waits, not one copy of the last one: a file with
    # hooks on two events alternates them, and matching only the newest would
    # let the queue grow for as long as the run in flight takes.
    let dir = testDir("serial_alternating")
    defer:
      removeDir(dir)
    let
      path = dir / "a.nim"
      log = dir / "log.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command: "sh -c 'sleep 0.2; echo write >> " & log & "'",
        timeout: 5,
      ),
      HookEntry(
        event: heBufReadPost, command: "sh -c 'echo read >> " & log & "'", timeout: 5
      ),
    ]

    # A write's hooks running.
    editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
    turn()

    for _ in 0 ..< 3:
      editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
      editor.queueHooks(heBufReadPost, path, SourceLanguage.langNim)
    check editor.hookJobs.mapIt(it.state) == @[jsRunning, jsWaiting, jsWaiting]

    editor.drain(
      proc(): bool =
        false
    )

    # The write's hooks in flight, then one run of each event, in the order
    # they first came.
    check readFile(log).splitLines.filterIt(it.len > 0) == @["write", "write", "read"]

  test "Hooks of different files never overlap":
    # What a command touches besides its file is unknown: two `git add` runs
    # at once already fail on the index lock.
    let dir = testDir("serial_otherfile")
    defer:
      removeDir(dir)
    let log = dir / "log"
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command:
          "sh -c 'echo \"start $1\" >> " & log & "; sleep 0.1; echo end >> " & log &
          "' sh ${filename}",
        timeout: 5,
      )
    ]

    for name in ["a.nim", "b.nim", "c.nim"]:
      editor.queueHooks(heBufWritePost, dir / name, SourceLanguage.langNim)
    turn()
    check editor.hookJobs.mapIt(it.state) == @[jsRunning, jsWaiting, jsWaiting]

    editor.drain(
      proc(): bool =
        editor.hookJobs.len == 0
    )
    check readFile(log).splitLines.filterIt(it.len > 0) ==
      @["start a.nim", "end", "start b.nim", "end", "start c.nim", "end"]

  test "A command naming no file runs once for several files":
    # `make proto` after a `:wa` that wrote two .proto files: the same work.
    let dir = testDir("serial_samework")
    defer:
      removeDir(dir)
    let log = dir / "log"
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost, command: "sh -c 'echo ran >> " & log & "'", timeout: 5
      )
    ]

    for name in ["a.proto", "b.proto"]:
      editor.queueHooks(heBufWritePost, dir / name, SourceLanguage.langNone)
    check editor.hookJobs.len == 1

    editor.drain(
      proc(): bool =
        editor.hookJobs.len == 0
    )
    check readFile(log).splitLines.filterIt(it.len > 0) == @["ran"]

  test "A read never takes the place of an owed write":
    # The same command on both events is still two pieces of work: a quit
    # waits for the write's.
    let dir = testDir("serial_owed")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    writeFile(path, "x\n")
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries = @[
      HookEntry(event: heBufWritePost, command: "true", timeout: 5),
      HookEntry(event: heBufReadPost, command: "true", timeout: 5),
    ]

    editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
    editor.queueHooks(heBufReadPost, path, SourceLanguage.langNim)
    check editor.hookJobs.mapIt(it.owed) == @[true, false]
    discard editor.stopRunningCommands()

  test ":jobs lists a file's hooks":
    let dir = testDir("listed")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries =
      @[HookEntry(event: heBufWritePost, command: "sleep 5", timeout: 10)]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    check editor.runningCommands() ==
      @["BufWritePost hook (sleep) (queued): " & dir / "a.nim"]
    turn()
    check editor.runningCommands() ==
      @["BufWritePost hook (sleep) (0s): " & dir / "a.nim"]
    discard editor.stopRunningCommands()

  test "A firing after `:jobs!` is not collapsed into one it doomed":
    # The stop dropped the first, so the second has to run.
    let dir = testDir("collapse_epoch")
    defer:
      removeDir(dir)
    let
      path = dir / "a.nim"
      log = dir / "log"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost, command: "sh -c 'echo ran >> " & log & "'", timeout: 5
      )
    ]

    editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
    discard editor.stopRunningCommands()
    editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
    check editor.hookJobs.len == 1

    editor.drain(
      proc(): bool =
        fileExists(log)
    )
    check fileExists(log) and readFile(log).splitLines.filterIt(it.len > 0) == @["ran"]

  test ":jobs! stops the rest of a hook batch already in flight":
    # The kill reaches the command that is running; the entries behind it are
    # held in the job's own loop, which checks the stop between them.
    let dir = testDir("stopbatch")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    writeFile(path, "foo\n")
    let log = dir / "log"
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command: "sh -c 'echo one >> ${dir}/log; sleep 0.4'",
        timeout: 5,
      ),
      HookEntry(
        event: heBufWritePost, command: "sh -c 'echo two >> ${dir}/log'", timeout: 5
      ),
      HookEntry(
        event: heBufWritePost, command: "sh -c 'echo three >> ${dir}/log'", timeout: 5
      ),
    ]

    editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        fileExists(log)
    )

    discard editor.stopRunningCommands()
    # Well past what the two entries behind it would need to run.
    for _ in 0 ..< 40:
      waitFor sleepAsync(10.milliseconds)

    check readFile(log).splitLines.filterIt(it.len > 0) == @["one"]

  test "A hook the user stopped is not reported as failing":
    let dir = testDir("stopsilent")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    editor.config.hooks.entries =
      @[HookEntry(event: heBufWritePost, command: "sleep 5", timeout: 10)]

    editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
    turn()
    check editor.stopRunningCommands() == 1
    editor.drain(
      proc(): bool =
        editor.hookJobs.len == 0
    )

    check editor.hookJobs.len == 0
    check "sleep" notin editor.state.statusMessage

suite "Hooks - what fires nothing":
  test "A utility buffer fires nothing":
    # The filer and the file tree sidebar hold the directory they are listing
    # in `filePath`, and the filer is rebuilt as a new buffer on every
    # directory change.
    let dir = testDir("utility")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries =
      @[HookEntry(event: heBufReadPost, command: "true", timeout: 5)]

    let filerLike = newTextBuffer("")
    filerLike.filePath = some(dir)
    filerLike.isUtilityBuffer = true
    editor.queueHooks(heBufReadPost, filerLike)
    check editor.hookJobs.len == 0

  test "A directory path fires nothing":
    let dir = testDir("dirpath")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries = @[
      HookEntry(event: heBufWritePost, command: "true", timeout: 5),
      HookEntry(event: heBufReadPost, command: "true", timeout: 5),
    ]

    editor.queueHooks(heBufWritePost, dir, SourceLanguage.langNone)
    editor.queueHooks(heBufReadPost, dir, SourceLanguage.langNone)
    check editor.hookJobs.len == 0

suite "Hooks - reading a file back":
  test "BufReadPost fires on `:e!`, not only on an open":
    let dir = testDir("readpost")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    editor.config.hooks.entries =
      @[HookEntry(event: heBufReadPost, command: "true", timeout: 5)]

    writeFile(path, "z\n")
    check editor.reloadCurrentFile().isOk

    # The buffer now holds what the file holds, which is what the event says.
    check editor.hookJobs.mapIt(it.label) == @["BufReadPost hook (true)"]

  test "BufReadPost fires when a backup is restored into the buffer":
    let dir = testDir("restore")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "current\n")
    editor.config.autoBackup.backupDir = some(dir / "backups")
    let backupDir = dir / "backups" / "a"
    createDir(backupDir)
    writeFile(backupDir / "backup.json", $(%*{"path": absolutePath(path)}))
    writeFile(backupDir / "2025-01-15T10:30:45+09:00", "restored\n")
    editor.config.hooks.entries =
      @[HookEntry(event: heBufReadPost, command: "true", timeout: 5)]

    check editor.processViewerResult(HandlerResult(kind: hrEnterBackupManager))
    check editor.processBackupResult(
      HandlerResult(kind: hrBackupManagerRestore, restoreBackupIndex: 0)
    )

    check readFile(path) == "restored\n"
    check editor.hookJobs.mapIt(it.label) == @["BufReadPost hook (true)"]

  test "A file an LSP rename opens in the background is not a read":
    let dir = testDir("background")
    defer:
      removeDir(dir)
    let path = dir / "b.nim"
    writeFile(path, "x\n")
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries =
      @[HookEntry(event: heBufReadPost, command: "true", timeout: 5)]

    check editor.openFileInBackground(path).isOk
    check editor.hookJobs.len == 0

  test "A reload the user did not ask for is not a read":
    let dir = testDir("quietreload")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    editor.config.hooks.entries =
      @[HookEntry(event: heBufReadPost, command: "true", timeout: 5)]

    writeFile(path, "z\n")
    check editor.reloadCurrentFile(announce = false).isOk
    check editor.hookJobs.len == 0

suite "Hooks - a file changed on disk":
  test "A change the watcher picks up fires no BufReadPost":
    # Unlike `:e!`: nothing tells a read hook's own rewrite apart from
    # another program's.
    let dir = testDir("watcher")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    editor.config.standard.liveReloadOfFile = true
    editor.state.timing.fileModCheckInterval = 0
    editor.config.hooks.entries =
      @[HookEntry(event: heBufReadPost, command: "true", timeout: 5)]

    writeFile(path, "from elsewhere, longer\n")
    editor.maybeReloadExternallyModifiedFile()
    check editor.activeBuffer.getLine(0) == "from elsewhere, longer"
    check editor.hookJobs.len == 0

  test "A read hook that rewrites its file does not feed itself":
    let dir = testDir("readloop")
    defer:
      removeDir(dir)
    let
      path = dir / "a.nim"
      log = dir / "log"
    writeFile(path, "x\n")
    let editor = newEditor(newEditorConfig())
    editor.config.standard.liveReloadOfFile = true
    editor.state.timing.fileModCheckInterval = 0
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufReadPost,
        # Not idempotent: every run changes the file again.
        command: "sh -c 'echo stamp >> ${file}; echo ran >> " & log & "'",
        timeout: 5,
      )
    ]

    check editor.loadFile(path).isOk
    for _ in 0 ..< 3:
      editor.drain(
        proc(): bool =
          editor.hookJobs.len == 0
      )
      editor.maybeReloadExternallyModifiedFile()

    check readFile(log).splitLines.filterIt(it.len > 0).len == 1
    check editor.activeBuffer.getLine(1) == "stamp"

suite "Hooks - quitting":
  test "`:wq` waits for the write's hooks before the session ends":
    let dir = testDir("wq")
    defer:
      removeDir(dir)
    let
      path = dir / "a.nim"
      log = dir / "log"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    discard editor.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "y")
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command: "sh -c 'sleep 0.2; echo ran >> " & log & "'",
        timeout: 5,
      )
    ]

    check not editor.noteQuit(
      editor.processSaveAndQuitResult(
        HandlerResult(
          kind: hrSaveAndQuit,
          saveAndQuitFilename: none(string),
          forceQuitAfterSave: false,
        )
      )
    )
    check not editor.readyToExit()
    # The screen stays up and says what it is waiting for.
    check "Waiting" in editor.state.statusMessage

    editor.drain(
      proc(): bool =
        editor.readyToExit()
    )

    check editor.readyToExit()
    check readFile(log).splitLines.filterIt(it.len > 0) == @["ran"]

  test "A quit that wrote nothing waits for nothing":
    let dir = testDir("quitnowrite")
    defer:
      removeDir(dir)
    let
      path = dir / "a.nim"
      log = dir / "log"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufReadPost, command: "sh -c 'echo ran >> " & log & "'", timeout: 5
      )
    ]

    # A read is moot once the user leaves, so it is dropped.
    editor.queueHooks(heBufReadPost, path, SourceLanguage.langNim)
    check not editor.noteQuit(false)
    check editor.readyToExit()
    check "Waiting" notin editor.state.statusMessage

    editor.drain(
      proc(): bool =
        false
    )
    check not fileExists(log)

  test "Nothing new is queued once the user quit":
    let dir = testDir("quitqueue")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    editor.config.hooks.entries =
      @[HookEntry(event: heBufWritePost, command: "true", timeout: 5)]

    check not editor.noteQuit(false)
    editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
    check editor.hookJobs.len == 0

  test "A write hook already running when the quit comes is waited for":
    let dir = testDir("quitrunning")
    defer:
      removeDir(dir)
    let
      path = dir / "a.nim"
      log = dir / "log"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command: "sh -c 'sleep 0.3; echo ran >> " & log & "'",
        timeout: 5,
      )
    ]

    # Started by an earlier `:w`, then `:q`.
    editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
    turn()
    check editor.hookJobs.mapIt(it.state) == @[jsRunning]

    check not editor.noteQuit(false)
    check not editor.readyToExit()
    editor.drain(
      proc(): bool =
        editor.readyToExit()
    )

    check readFile(log).splitLines.filterIt(it.len > 0) == @["ran"]

  test "Stopping the commands ends the wait":
    # What Ctrl-C and a signal after the quit come down to: a hook with no
    # bound of its own cannot hold the session open.
    let dir = testDir("quitstuck")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    editor.config.hooks.entries =
      @[HookEntry(event: heBufWritePost, command: "sleep 60", timeout: 0)]

    editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
    turn()
    check not editor.noteQuit(false)
    check not editor.readyToExit()

    let start = Moment.now()
    discard editor.stopRunningCommands()
    editor.drain(
      proc(): bool =
        editor.readyToExit()
    )

    check editor.readyToExit()
    check Moment.now() - start < 2.seconds

  test "Ctrl-C stops the hooks the quit waits for and says so":
    let dir = testDir("quitctrlc")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    editor.config.hooks.entries = @[
      HookEntry(event: heBufWritePost, command: "sleep 60", timeout: 0),
      HookEntry(event: heBufWritePost, command: "true", timeout: 5),
    ]

    editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
    check not editor.noteQuit(false)
    turn()
    check editor.hookJobs.mapIt(it.state) == @[jsRunning]

    editor.abandonExitWait()
    # Killed at once: the session may end on this very turn.
    check editor.readyToExit()
    # A write the hooks never finished following is worth a line on stderr.
    check editor.state.exitReports ==
      @["Stopped before finishing: BufWritePost hooks (sleep, true) on " & path]
    # The session's end comes through here again, and names nothing twice.
    editor.abandonExitWait()
    check editor.state.exitReports.len == 1
    editor.drain(
      proc(): bool =
        editor.hookJobs.len == 0
    )
    check editor.hookJobs.len == 0

  test "Ctrl-C reports the owed hooks it keeps from starting":
    let dir = testDir("quitctrlc_queued")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    editor.config.hooks.entries =
      @[HookEntry(event: heBufWritePost, command: "true", timeout: 5)]

    editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
    check not editor.noteQuit(false)
    editor.abandonExitWait()

    check editor.hookJobs.len == 0
    check editor.state.exitReports == @["Not run: BufWritePost hook (true) on " & path]

  test "The wait says how to stop it, whatever reported meanwhile":
    let dir = testDir("quithint")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    editor.config.hooks.entries =
      @[HookEntry(event: heBufWritePost, command: "sleep 5", timeout: 10)]

    editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
    check not editor.noteQuit(false)
    turn()
    # A QuickRun drained with the quit reporting over the status line.
    editor.state.statusMessage = "QuickRun completed"
    editor.showExitWait()
    check "Ctrl-C" in editor.state.statusMessage

    editor.abandonExitWait()

  test "The wait is logged once, not once per frame":
    let dir = testDir("quitlog")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    editor.config.hooks.entries =
      @[HookEntry(event: heBufWritePost, command: "sleep 5", timeout: 10)]

    clearMessageLog()
    editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
    check not editor.noteQuit(false)
    for _ in 0 ..< 10:
      editor.showExitWait()
    check getMessageLog().countIt("Waiting" in it) == 1

    editor.abandonExitWait()

  test "Other work queued ahead of the quit still runs":
    # `:!cmd` and `:q` from one mapping land in one event; the quit must not
    # swallow what came before it.
    let dir = testDir("quitdrain")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "b\na\n")
    let buf = editor.activeBuffer
    editor.state.pending.add PendingAsyncOp(
      kind: paoFilter,
      filter: (
        bufferId: buf.id,
        windowIndex: editor.windowManager.activeWindowIndex,
        command: "sort",
        first: 0,
        last: 1,
        contentVersion: buf.contentVersion,
      ),
    )

    check not editor.noteQuit(false)
    editor.drain(
      proc(): bool =
        buf.getLine(0) == "a"
    )

    check buf.getLine(0) == "a"

  test "`:wqa` waits for every file's hooks, one after another":
    let dir = testDir("quitserial")
    defer:
      removeDir(dir)
    let log = dir / "log"
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command: "sh -c 'sleep 0.1; echo \"$1\" >> " & log & "' sh ${filename}",
        timeout: 5,
      )
    ]
    for name in ["a.nim", "b.nim", "c.nim"]:
      writeFile(dir / name, "x\n")
      editor.queueHooks(heBufWritePost, dir / name, SourceLanguage.langNim)
    check editor.hookJobs.len == 3

    check not editor.noteQuit(false)
    editor.drain(
      proc(): bool =
        editor.readyToExit()
    )

    check editor.readyToExit()
    check readFile(log).splitLines.filterIt(it.len > 0) == @["a.nim", "b.nim", "c.nim"]

  test "A hook that fails while the quit waits is kept for stderr":
    let dir = testDir("quitfail")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost, command: "sh -c 'echo broke; exit 3'", timeout: 5
      )
    ]

    # A failure before the quit was on screen already.
    editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
    editor.drain(
      proc(): bool =
        editor.hookJobs.len == 0
    )
    check editor.state.exitReports.len == 0

    editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
    check not editor.noteQuit(false)
    editor.drain(
      proc(): bool =
        editor.readyToExit()
    )

    check editor.state.exitReports.len == 1
    check "exited with 3: broke" in editor.state.exitReports[0]
    # The status line still says how to stop waiting.
    check "Ctrl-C" in editor.state.statusMessage

  test "The output a hook shows while the quit waits goes to stderr":
    # The split would go with the screen, a moment after it opened.
    let dir = testDir("quitshow")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    let bufferCount = editor.buffers.len
    editor.config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command: "sh -c 'echo finding 1; echo finding 2'",
        showOutput: true,
        timeout: 5,
      )
    ]

    editor.queueHooks(heBufWritePost, path, SourceLanguage.langNim)
    check not editor.noteQuit(false)
    editor.drain(
      proc(): bool =
        editor.readyToExit()
    )

    check editor.buffers.len == bufferCount
    check editor.state.exitReports ==
      @["BufWritePost hook (sh) output for " & path & ":\nfinding 1\nfinding 2"]

  test "A failure of a hook the quit does not wait for stays off stderr":
    let dir = testDir("quitotherfail")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    editor.config.hooks.entries = @[
      HookEntry(event: heBufReadPost, command: "sh -c 'sleep 0.2; exit 1'", timeout: 5)
    ]

    editor.queueHooks(heBufReadPost, path, SourceLanguage.langNim)
    turn()
    check not editor.noteQuit(false)
    editor.drain(
      proc(): bool =
        editor.hookJobs.len == 0
    )

    check editor.hookJobs.len == 0
    check editor.state.exitReports.len == 0

  test "Control bytes in a path do not reach the terminal":
    let dir = testDir("ctlpath")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.config.hooks.entries =
      @[HookEntry(event: heBufWritePost, command: "${dir}/\e[31mrun", timeout: 5)]

    editor.queueHooks(heBufWritePost, dir / "a.nim", SourceLanguage.langNim)
    check not editor.noteQuit(false)
    editor.drain(
      proc(): bool =
        editor.readyToExit()
    )

    check editor.state.exitReports.len == 1
    check '\e' notin editor.state.exitReports[0]

  test "Nothing is auto-saved while the quit waits":
    # `:q!` threw the changes away; the frames drawn while the owed hooks run
    # must not write them after all.
    let dir = testDir("quitautosave")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\n")
    editor.config.autoSave.enable = true
    editor.config.autoSave.interval = 0
    check editor.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "y").isOk

    check not editor.noteQuit(false)
    editor.tick()

    check readFile(path) == "x\n"
