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

import std/[unittest, monotimes, options, os, strutils, tables]

import pkg/[chronos, results]

import
  ../src/moepkg/[
    buffer, types, editor, config, hooks, hook_ex_command, editor_file, editor_frame,
    editor_hooks, editor_window, job_lanes,
  ]
import ../src/moepkg/handler {.all.}
import ../src/moepkg/command_handlers/[handler_result, editor_ops, file_ops]
from ../src/moepkg/key_bindings/registry import parseKeyCombo

when defined(posix):
  from std/posix import getuid

when defined(linux):
  import std/atomics
  from std/posix import SIGTERM
  import ../src/moepkg/signal_watcher_linux {.all.}

proc testDir(name: string): string =
  ## A directory of this run's own, as in test_hooks_run.
  result =
    getTempDir() / ("moe_test_hook_write_pre_" & $getCurrentProcessId() & "_" & name)
  removeDir(result)
  createDir(result)

proc openInEditor(e: Editor, path: string, content: string) =
  writeFile(path, content)
  discard e.loadFile(path)
  discard e.jobLanes.stopAll()

proc addBackground(e: Editor, path: string, content: string): TextBuffer =
  ## A second file's buffer, registered but shown in no window, modified.
  writeFile(path, content & "\n")
  result = newTextBuffer(content, some(path))
  result.noteFileStamp(path)
  e.addBuffer(result)
  doAssert result.insertText(BufferPosition(line: 0, column: 0), "new ").isOk

proc writePre(command: string, onFail = hfaWrite, filter = "", timeout = 5): HookEntry =
  HookEntry(
    event: heBufWritePre,
    command: command,
    onFail: onFail,
    filter: filter,
    timeout: timeout,
  )

proc writePreEx(exCommand: string, filter = ""): HookEntry =
  ## An entry running `exCommand`, read as the loader reads it.
  result = HookEntry(event: heBufWritePre, exCommand: exCommand, filter: filter)
  doAssert parseHookExCommand(exCommand).isOk, exCommand

proc lines(buf: TextBuffer): seq[string] =
  for i in 0 ..< buf.len:
    result.add buf.getLine(i)

proc edit(buf: TextBuffer, lines: seq[string]) =
  doAssert buf.replaceAllLines(lines).isOk

proc typeKeys(e: Editor, keys: openArray[string]) =
  for key in keys:
    doAssert e.handleKeyCombo(parseKeyCombo(key).get)

type Turns = ref object
  renders, finishes: int
  interrupt: bool

proc watch(e: Editor): Turns =
  ## Stand in for the frontend and count what the wait asks of it.
  let turns = Turns()
  proc render(): bool =
    inc turns.renders
    true

  proc interrupted(): bool =
    turns.interrupt

  proc finish() =
    inc turns.finishes

  e.blockingWait =
    BlockingWait(render: render, interrupted: interrupted, finish: finish)
  turns

suite "BufWritePre - the output becomes the buffer":
  test "What the command prints is what is written":
    let dir = testDir("replace")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "b\na\n")
    editor.config.hooks.entries = @[writePre("sort")]

    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isOk
    check saved.get.warnings.len == 0
    check editor.activeBuffer.lines == @["a", "b"]
    check readFile(path) == "a\nb\n"

  test "One undo takes the output back":
    let dir = testDir("undo")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "b\na\n")
    editor.config.hooks.entries = @[writePre("sort")]

    check editor.saveFile(editor.activeBuffer).isOk
    check editor.activeBuffer.undo().isOk
    check editor.activeBuffer.lines == @["b", "a"]

  test "Entries run in order, each on what the one before printed":
    let dir = testDir("chain")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "a\n")
    editor.config.hooks.entries = @[writePre("sed s/a/b/"), writePre("sed s/b/c/")]

    check editor.saveFile(editor.activeBuffer).isOk
    check readFile(path) == "c\n"

  test "The cursor stays on its line when lines come above it":
    let dir = testDir("cursor")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\ny\nz\n")
    editor.config.hooks.entries = @[writePre("sh -c 'echo header; cat'")]
    editor.activeWindow.cursor = BufferPosition(line: 2, column: 0)

    check editor.saveFile(editor.activeBuffer).isOk
    check editor.activeBuffer.lines == @["header", "x", "y", "z"]
    check editor.activeWindow.cursor.line == 3

  test "The cursor keeps the column vertical moves want across the write":
    let dir = testDir("wanted")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "abcdef\nab\nabcdef\n")
    editor.config.hooks.entries = @[writePre("sh -c 'echo header; cat'")]

    editor.typeKeys(["5", "l", "j"])
    check editor.activeWindow.cursor == BufferPosition(line: 1, column: 1)
    editor.typeKeys([":", "w", "Enter"])
    check editor.activeBuffer.lines == @["header", "abcdef", "ab", "abcdef"]
    check editor.activeWindow.cursor == BufferPosition(line: 2, column: 1)
    editor.typeKeys(["j"])
    check editor.activeWindow.cursor == BufferPosition(line: 3, column: 5)

  test "The cursor keeps the column vertical moves want when other lines change":
    let dir = testDir("wantedstill")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "abcdef\nab\nabcdef\nx\n")
    editor.config.hooks.entries = @[writePre("sed s/x/y/")]

    editor.typeKeys(["5", "l", "j", ":", "w", "Enter"])
    check editor.activeBuffer.lines == @["abcdef", "ab", "abcdef", "y"]
    check editor.activeWindow.cursor == BufferPosition(line: 1, column: 1)
    editor.typeKeys(["j"])
    check editor.activeWindow.cursor == BufferPosition(line: 2, column: 5)

  test "The view moves with the text above it":
    let dir = testDir("topline")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    var content = ""
    for i in 0 ..< 40:
      content.add $i & "\n"
    editor.openInEditor(path, content)
    editor.config.hooks.entries =
      @[writePre("sh -c 'echo one; echo two; echo three; cat'")]
    editor.activeWindow.cursor = BufferPosition(line: 12, column: 0)
    editor.activeWindow.viewport.topLine = 10

    check editor.saveFile(editor.activeBuffer).isOk
    check editor.activeWindow.cursor.line == 15
    check editor.activeWindow.viewport.topLine == 13

  test "Another window on the buffer moves with its text once":
    let dir = testDir("other_window")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "x\ny\nz\nw\n")
    check editor.vsplit().isOk
    let other = editor.windowManager.windows[1 - editor.windowManager.activeWindowIndex]
    other.cursor = BufferPosition(line: 1, column: 0)
    editor.config.hooks.entries = @[writePre("sh -c 'echo header; cat'")]

    check editor.saveFile(editor.activeBuffer).isOk
    check editor.activeBuffer.lines == @["header", "x", "y", "z", "w"]
    check other.cursor.line == 2

  test "The command gets the file's own line endings, and they stay":
    let dir = testDir("crlf")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "a\r\nb\r\n")
    editor.config.hooks.entries =
      @[writePre("sh -c 'cat > \"$0\"; cat \"$0\"' ${dir}/seen")]

    check editor.saveFile(editor.activeBuffer).isOk
    check readFile(dir / "seen") == "a\r\nb\r\n"
    check editor.activeBuffer.lines == @["a", "b"]
    check readFile(path) == "a\r\nb\r\n"

  test "A file without a newline at its end is written without one":
    let dir = testDir("noeol")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "b\na")
    editor.config.hooks.entries =
      @[writePre("sh -c 'cat > \"$0\"; sort \"$0\"' ${dir}/seen")]

    check editor.saveFile(editor.activeBuffer).isOk
    # The command reads a last line that ends, as text tools expect.
    check readFile(dir / "seen") == "b\na\n"
    check editor.activeBuffer.lines == @["a", "b"]
    check readFile(path) == "a\nb"

  test "An unchanged answer keeps an empty last line of a file without an end":
    let dir = testDir("noeolblank")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "a")
    editor.activeBuffer.edit(@["a", ""])
    editor.config.hooks.entries = @[writePre("cat")]

    check editor.saveFile(editor.activeBuffer).isOk
    check editor.activeBuffer.lines == @["a", ""]
    check readFile(path) == "a\n"

  test "The command gets the file's own encoding, and its answer is read in it":
    let dir = testDir("utf16")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let bytes = "\xFF\xFEa\x00\n\x00"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, bytes)
    editor.config.hooks.entries =
      @[writePre("sh -c 'cat > \"$0\"; cat \"$0\"' ${dir}/seen")]

    check editor.saveFile(editor.activeBuffer).isOk
    check readFile(dir / "seen") == bytes
    check editor.activeBuffer.lines == @["a"]
    check readFile(path) == bytes

suite "BufWritePre - failures":
  test "A command that fails leaves the buffer, and the write goes ahead":
    let dir = testDir("failwrite")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "old\n")
    editor.activeBuffer.edit(@["new"])
    editor.config.hooks.entries =
      @[writePre("sh -c 'echo first problem >&2; echo more >&2; exit 1'")]

    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isOk
    check saved.get.warnings.len == 1
    check "exited with 1: first problem" in saved.get.warnings[0]
    check editor.activeBuffer.lines == @["new"]
    check readFile(path) == "new\n"

  test "onFail = abort keeps the file as it was":
    let dir = testDir("failabort")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "old\n")
    editor.activeBuffer.edit(@["new"])
    editor.config.hooks.entries = @[writePre("false", onFail = hfaAbort)]

    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isErr
    check "not written" in saved.error
    check readFile(path) == "old\n"

  test "Printing nothing is a failure, not an emptied file":
    let dir = testDir("empty")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "keep\n")
    editor.config.hooks.entries = @[writePre("true")]

    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isOk
    check saved.get.warnings.len == 1
    check "wrote nothing back" in saved.get.warnings[0]
    check readFile(path) == "keep\n"

  test "Blank text may be emptied":
    let dir = testDir("blank")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "  \n\t\n\n")
    editor.config.hooks.entries =
      @[writePre("sh -c 'cat >/dev/null'", onFail = hfaAbort)]

    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isOk
    check saved.get.warnings.len == 0
    check editor.activeBuffer.lines == @[""]

  test "filter.maxOutputSize = 0 puts no limit on the answer":
    let dir = testDir("nolimit")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "a\n")
    editor.config.filter.maxOutputSize = 0
    editor.config.hooks.entries = @[writePre("sh -c 'cat; seq 1 100'")]

    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isOk
    check saved.get.warnings.len == 0
    check editor.activeBuffer.len == 101

  test "An answer that is not the buffer's encoding is refused":
    let dir = testDir("badbytes")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "keep\n")
    editor.config.hooks.entries = @[writePre("printf '\\377\\n'")]

    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isOk
    check saved.get.warnings.len == 1
    check "not valid UTF-8" in saved.get.warnings[0]
    check editor.activeBuffer.lines == @["keep"]

  test "A failure ends the chain":
    let dir = testDir("chainstop")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "a\n")
    editor.config.hooks.entries =
      @[writePre("false"), writePre("sh -c 'touch \"$0\"; cat' ${dir}/second")]

    check editor.saveFile(editor.activeBuffer).isOk
    check not fileExists(dir / "second")

  test "A buffer of raw bytes is written as it is":
    let dir = testDir("raw")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "a\xFFb\n")
    editor.config.hooks.entries = @[writePre("sh -c 'touch \"$0\"; cat' ${dir}/ran")]

    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isOk
    check saved.get.warnings.len == 1
    check not fileExists(dir / "ran")
    check readFile(path) == "a\xFFb\n"

suite "BufWritePre - an Ex command":
  proc setup(name, content: string, entries: seq[HookEntry]): (Editor, string, string) =
    let dir = testDir(name)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, content)
    editor.config.hooks.entries = entries
    (editor, dir, path)

  test "stripwhitespace strips what is written, and one undo takes it back":
    let (editor, dir, path) =
      setup("ex_strip", "a  \nb\t\nc\n", @[writePreEx("stripwhitespace")])
    defer:
      removeDir(dir)
    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isOk
    check saved.get.warnings.len == 0
    check readFile(path) == "a\nb\nc\n"
    check editor.activeBuffer.lines == @["a", "b", "c"]
    check editor.activeBuffer.undo().isOk
    check editor.activeBuffer.lines == @["a  ", "b\t", "c"]

  test "A range backwards in a short file changes nothing, as in Vim":
    let (editor, dir, path) = setup("ex_short", "a,\n", @[writePreEx("1,$-1s/,$//")])
    defer:
      removeDir(dir)
    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isOk
    check saved.get.warnings.len == 1
    check "Invalid range" in saved.get.warnings[0]
    check readFile(path) == "a,\n"

  test "stripwhitespace on a clean file makes no change":
    let (editor, dir, _) = setup("ex_clean", "a\nb\n", @[writePreEx("stripwhitespace")])
    defer:
      removeDir(dir)
    let changeId = editor.activeBuffer.currentChangeId
    check editor.saveFile(editor.activeBuffer).isOk
    check editor.activeBuffer.currentChangeId == changeId

  test "An open change runs no entry, and the text is written as it is":
    let (editor, dir, path) =
      setup("ex_open", "a  \n", @[writePreEx("stripwhitespace"), writePre("sort")])
    defer:
      removeDir(dir)
    check editor.activeBuffer.beginTransaction("insert").isOk
    let saved = editor.saveFile(editor.activeBuffer)
    check editor.activeBuffer.commitTransaction().isOk
    check saved.isOk
    check saved.get.warnings.len == 1
    check "a change is in progress" in saved.get.warnings[0]
    check readFile(path) == "a  \n"

  test "An open change with an `abort` program refuses the write":
    let (editor, dir, path) =
      setup("ex_open_abort", "b\na\n", @[writePre("sort", onFail = hfaAbort)])
    defer:
      removeDir(dir)
    check editor.activeBuffer.beginTransaction("insert").isOk
    let saved = editor.saveFile(editor.activeBuffer)
    check editor.activeBuffer.commitTransaction().isOk
    check saved.isErr
    check "a change is in progress" in saved.error
    check "not written" in saved.error
    check readFile(path) == "b\na\n"

  test "A :s with no closing delimiter keeps the blanks it ends with":
    let (editor, dir, path) =
      setup("ex_trailing", "\ta\n", @[writePreEx("%s/\\t/    ")])
    defer:
      removeDir(dir)
    check editor.saveFile(editor.activeBuffer).isOk
    check readFile(path) == "    a\n"

  test "A :s with `e` that finds nothing writes without a word":
    let (editor, dir, path) = setup("ex_e", "a\n", @[writePreEx(r"%s/\s+$//e")])
    defer:
      removeDir(dir)
    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isOk
    check saved.get.warnings.len == 0
    check readFile(path) == "a\n"

  test "A :s without `e` that finds nothing warns, writes, and the next entry runs":
    let (editor, dir, path) =
      setup("ex_noe", "a\n", @[writePreEx(r"%s/zzz//"), writePreEx(r"%s/a/b/")])
    defer:
      removeDir(dir)
    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isOk
    check saved.get.warnings ==
      @["BufWritePre hook (:%s/zzz//) failed: Pattern not found: zzz"]
    check readFile(path) == "b\n"

  test "Its warning stays when a program after it stops the write":
    let (editor, dir, _) = setup(
      "ex_refused",
      "a\n",
      @[writePreEx("%s/zzz//"), writePre("false", onFail = hfaAbort)],
    )
    defer:
      removeDir(dir)
    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isErr
    check "Pattern not found: zzz" in saved.error
    check "not written" in saved.error

  test "An empty match that changes no line makes no change":
    let (editor, dir, path) = setup("ex_empty", "a\nb\n", @[writePreEx(r"%s/\s*$//e")])
    defer:
      removeDir(dir)
    let version = editor.activeBuffer.contentVersion
    check editor.saveFile(editor.activeBuffer).isOk
    check editor.activeBuffer.contentVersion == version
    check editor.activeBuffer.undo().isErr
    check readFile(path) == "a\nb\n"

  test "A range past the end warns and the file is written":
    let (editor, dir, path) = setup("ex_range", "a\n", @[writePreEx("1,10s/a/b/")])
    defer:
      removeDir(dir)
    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isOk
    check saved.get.warnings.len == 1
    check "1,10s/a/b/" in saved.get.warnings[0]
    check readFile(path) == "a\n"

  test "An entry built in code that does not read warns, and the file is written":
    let (editor, dir, path) =
      setup("ex_unread", "a\n", @[HookEntry(event: heBufWritePre, exCommand: "s/a/b/")])
    defer:
      removeDir(dir)
    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isOk
    check saved.get.warnings.len == 1
    check "expected" in saved.get.warnings[0]
    check readFile(path) == "a\n"

  test "A closed fold does not widen the range":
    let (editor, dir, path) =
      setup("ex_fold", "a\na\na\na\na\n", @[writePreEx("1,3s/a/b/")])
    defer:
      removeDir(dir)
    check editor.activeBuffer.foldState.addFold(2, 4, collapsed = true)
    check editor.saveFile(editor.activeBuffer).isOk
    check readFile(path) == "b\nb\nb\na\na\n"

  test "The case goes by 'ignorecase' and 'smartcase' and the flags fix it":
    let (editor, dir, path) = setup(
      "ex_case",
      "Ab\nAb\nAb\nAb\n",
      @[
        writePreEx("1s/a/x/"),
        writePreEx("2s/A/y/"),
        writePreEx("3s/a/z/I"),
        writePreEx("4s/(?-i)a/w/e"),
      ],
    )
    defer:
      removeDir(dir)
    editor.state.input.search.ignorecase = true
    editor.state.input.search.smartcase = true
    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isOk
    check readFile(path) == "xb\nyb\nAb\nAb\n"
    check saved.get.warnings.len == 1

  test "The cursor, the view, the searches, the jumps and the message stay":
    var content = ""
    for i in 0 ..< 40:
      content.add "line " & $i & "   \n"
    let (editor, dir, _) = setup(
      "ex_state", content, @[writePreEx("stripwhitespace"), writePreEx(r"%s/line/l/g")]
    )
    defer:
      removeDir(dir)
    editor.activeWindow.cursor = BufferPosition(line: 12, column: 8)
    editor.activeWindow.viewport.topLine = 10
    editor.state.input.search.history = @["before"]
    editor.state.input.search.last.pattern = "before"
    editor.state.input.commandState.history = @["cmd"]
    let jumps = editor.state.jumpList
    editor.state.statusMessage = ""

    check editor.saveFile(editor.activeBuffer).isOk
    check editor.activeBuffer.getLine(12) == "l 12"
    # On the line it was, clamped onto its shorter text.
    check editor.activeWindow.cursor == BufferPosition(line: 12, column: 3)
    check editor.activeWindow.viewport.topLine == 10
    check editor.state.input.search.history == @["before"]
    check editor.state.input.search.last.pattern == "before"
    check editor.state.input.commandState.history == @["cmd"]
    check editor.state.jumpList == jumps
    check editor.state.statusMessage == ""

  test ":wa runs it on a file no window shows":
    let (editor, dir, _) = setup("ex_wa", "a\n", @[writePreEx("%s/old/OLD/")])
    defer:
      removeDir(dir)
    discard editor.addBackground(dir / "b.txt", "old")
    let saved = editor.saveAllBuffers()
    check saved.failures.len == 0
    check readFile(dir / "b.txt") == "new OLD\n"

  test "It runs in order with programs, and a failed program stops it":
    let (editor, dir, path) = setup(
      "ex_order",
      "a\n",
      @[writePreEx("%s/a/b/"), writePre("sed s/b/c/"), writePreEx("%s/c/d/")],
    )
    defer:
      removeDir(dir)
    check editor.saveFile(editor.activeBuffer).isOk
    check readFile(path) == "d\n"

    editor.activeBuffer.edit(@["a"])
    editor.config.hooks.entries = @[writePre("false"), writePreEx("%s/a/b/")]
    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isOk
    check saved.get.warnings.len == 1
    check readFile(path) == "a\n"

  test "A read-only buffer runs none":
    let (editor, dir, _) = setup("ex_ro", "a  \n", @[writePreEx("stripwhitespace")])
    defer:
      removeDir(dir)
    editor.activeBuffer.readOnly = true
    discard editor.saveFile(editor.activeBuffer, force = true)
    check editor.activeBuffer.lines == @["a  "]

  test "A copy written with :w {file} runs none":
    let (editor, dir, _) = setup("ex_copy", "a  \n", @[writePreEx("stripwhitespace")])
    defer:
      removeDir(dir)
    check editor.saveFile(editor.activeBuffer, some(dir / "copy.txt")).isOk
    check readFile(dir / "copy.txt") == "a  \n"
    check editor.activeBuffer.lines == @["a  "]

suite "BufWritePre - the wait":
  test "Ctrl-C stops the command and the file is not written":
    let dir = testDir("interrupt")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "old\n")
    editor.activeBuffer.edit(@["new"])
    editor.config.hooks.entries = @[writePre("sh -c 'sleep 5; cat'")]
    let turns = editor.watch
    turns.interrupt = true

    let start = Moment.now()
    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isErr
    check saved.error.startsWith("Interrupted")
    check Moment.now() - start < 2.seconds
    check readFile(path) == "old\n"
    check editor.activeBuffer.lines == @["new"]
    check turns.finishes == 1

  test "Ctrl-C stops a :wa, and the rest of it is not written":
    let dir = testDir("interruptall")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(dir / "a.txt", "old\n")
    editor.activeBuffer.edit(@["new"])
    discard editor.addBackground(dir / "b.txt", "old")
    editor.config.hooks.entries = @[writePre("sh -c 'sleep 5; cat'")]
    editor.watch.interrupt = true

    let saved = editor.saveAllBuffers()
    check saved.savedCount == 0
    # The file it never reached is said to be unsaved too.
    check saved.failures.len == 2
    check saved.failures[1].path == dir / "b.txt"
    check readFile(dir / "a.txt") == "old\n"
    check readFile(dir / "b.txt") == "old\n"

  test "Ctrl-C that comes as the command ends still leaves the buffer":
    let dir = testDir("interruptlate")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "old\n")
    editor.activeBuffer.edit(@["new"])
    # The command has printed and is about to exit when Ctrl-C comes; it is
    # over by the time the stop is acted on, so its answer stands.
    editor.config.hooks.entries =
      @[writePre("sh -c 'tr a-z A-Z; touch \"$0\"; sleep 0.2' ${dir}/printed")]
    discard editor.watch
    editor.blockingWait.interrupted = proc(): bool {.closure, gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if not fileExists(dir / "printed"):
          return false
        sleep 600
        true

    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isErr
    check saved.error.startsWith("Interrupted")
    check editor.activeBuffer.lines == @["new"]
    check readFile(path) == "old\n"

  test "Ctrl-C ends the macro that wrote":
    let dir = testDir("interruptmacro")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "abc\n")
    editor.config.hooks.entries = @[writePre("sh -c 'sleep 5; cat'")]
    editor.watch.interrupt = true
    editor.state.pendingInput.macroState.registers['q'] = @[":", "w", "<Enter>", "x"]

    for key in ["@", "q"]:
      check editor.handleKeyCombo(parseKeyCombo(key).get)
    check editor.activeBuffer.lines == @["abc"]
    check readFile(path) == "abc\n"

  when defined(linux):
    test "A deadly signal stops the command and the file is not written":
      # The loop answers the signal once the write is given up.
      let dir = testDir("signal")
      defer:
        removeDir(dir)
        taken.store(0)
      let path = dir / "a.txt"
      let editor = newEditor(newEditorConfig())
      editor.openInEditor(path, "old\n")
      editor.activeBuffer.edit(@["new"])
      editor.config.hooks.entries = @[writePre("sh -c 'sleep 5; cat'")]
      discard editor.watch
      editor.blockingWait.interrupted = proc(): bool =
        taken.store(SIGTERM.int)
        false

      let saved = editor.saveFile(editor.activeBuffer)
      check saved.isErr
      check saved.error.startsWith("Interrupted")
      check readFile(path) == "old\n"
      check editor.activeBuffer.lines == @["new"]

  test "A command that runs a while is named on the status line, then not":
    let dir = testDir("notice")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "a\n")
    editor.config.hooks.entries = @[writePre("sh -c 'sleep 0.6; cat'")]
    let shown = new string
    let turns = Turns()
    proc render(): bool =
      {.cast(gcsafe).}:
        inc turns.renders
        shown[] = editor.state.ui.waitNotice
      true

    editor.blockingWait.render = render

    check editor.saveFile(editor.activeBuffer).isOk
    check turns.renders == 1
    check "is running" in shown[]
    check editor.state.ui.waitNotice.len == 0

  test "The notice names each command in turn":
    let dir = testDir("noticeeach")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "a\n")
    editor.config.hooks.entries =
      @[writePre("sh -c 'sleep 0.5; cat'"), writePre("env sh -c 'sleep 0.5; cat'")]
    let shown = new seq[string]
    proc render(): bool =
      {.cast(gcsafe).}:
        shown[].add editor.state.ui.waitNotice
      true

    editor.blockingWait.render = render

    check editor.saveFile(editor.activeBuffer).isOk
    check shown[].len == 2
    check "(sh)" in shown[0]
    check "(env)" in shown[1]

  test "A command done before the notice is due draws nothing":
    let dir = testDir("quick")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "a\n")
    # Long enough for turns, well short of `WritePreNoticeDelay`.
    editor.config.hooks.entries = @[writePre("sh -c 'sleep 0.1; cat'")]
    let turns = editor.watch

    check WritePreNoticeDelay > 200.milliseconds
    check editor.saveFile(editor.activeBuffer).isOk
    check turns.renders == 0

  test "A frame drawn while the write waits runs no background work":
    let dir = testDir("notick")
    defer:
      removeDir(dir)
    let config = newEditorConfig()
    config.autoSave.enable = true
    config.autoSave.interval = 1
    let editor = newEditor(config)
    editor.openInEditor(dir / "a.txt", "a\n")
    discard editor.addBackground(dir / "b.txt", "old")
    editor.config.hooks.entries = @[writePre("sh -c 'sleep 0.5; cat'")]
    # An auto save is due.
    editor.state.timing.lastAutoSave = MonoTime()
    proc render(): bool =
      {.cast(gcsafe).}:
        {.cast(raises: []).}:
          editor.tick()
      true

    editor.blockingWait.render = render

    check editor.saveFile(editor.activeBuffer).isOk
    check readFile(dir / "b.txt") == "old\n"
    check not editor.waitingInPlace
    # Once the write is done, the auto save runs.
    editor.tick()
    check readFile(dir / "b.txt") == "new old\n"

  test "The input is handed back once, after every entry":
    let dir = testDir("finish")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "a\n")
    editor.config.hooks.entries = @[writePre("cat"), writePre("cat")]
    let turns = editor.watch

    check editor.saveFile(editor.activeBuffer).isOk
    check turns.finishes == 1

  test "Ex commands alone do not wait, so nothing is handed back":
    let dir = testDir("finish_ex")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "a \n")
    editor.config.hooks.entries = @[writePreEx("stripwhitespace")]
    let turns = editor.watch

    check editor.saveFile(editor.activeBuffer).isOk
    check readFile(path) == "a\n"
    check turns.finishes == 0
    check not editor.waitingInPlace

  test "The event loop does not run while the write waits":
    let dir = testDir("loop")
    defer:
      removeDir(dir)
    let path = dir / "a.txt"
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(path, "a\n")
    editor.config.hooks.entries = @[writePre("sh -c 'sleep 0.1; cat'")]
    let ran = new bool
    proc mark(ran: ref bool) {.async.} =
      await sleepAsync(1.milliseconds)
      ran[] = true

    let marking = mark(ran)
    check editor.saveFile(editor.activeBuffer).isOk
    check not ran[]
    waitFor marking
    check ran[]

suite "BufWritePre - which writes run it":
  test ":wa runs it for every file, and an abort keeps only its own file":
    let dir = testDir("writeall")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(dir / "a.txt", "old\n")
    editor.activeBuffer.edit(@["new"])
    discard editor.addBackground(dir / "b.txt", "old")
    editor.config.hooks.entries = @[
      writePre("false", onFail = hfaAbort, filter = r"a\.txt$"),
      writePre("tr a-z A-Z", filter = r"b\.txt$"),
    ]

    let saved = editor.saveAllBuffers()
    check saved.savedCount == 1
    check saved.failures.len == 1
    check readFile(dir / "a.txt") == "old\n"
    check readFile(dir / "b.txt").strip == "NEW OLD"

  test "A copy written with :w {file} runs none":
    let dir = testDir("copy")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(dir / "a.txt", "a\n")
    editor.config.hooks.entries = @[writePre("sh -c 'touch \"$0\"; cat' ${dir}/ran")]

    let saved = editor.saveFile(editor.activeBuffer, some(dir / "copy.txt"))
    check saved.isOk
    check saved.get.kind == wkCopy
    check not fileExists(dir / "ran")

  test "The save QuickRun makes runs it, and says what failed":
    let dir = testDir("quickrun")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    var config = newEditorConfig()
    config.quickRun.saveBufferWhenQuickRun = true
    let editor = newEditor(config)
    editor.openInEditor(path, "echo 1\n")
    editor.activeBuffer.edit(@["echo 2"])
    editor.config.hooks.entries = @[writePre("tr a-z A-Z"), writePre("false")]

    let prepared = editor.prepareQuickRun(editor.activeBuffer)
    require prepared.isOk
    check readFile(path) == "ECHO 2\n"
    check prepared.get.warnings.len == 1
    check "exited with 1" in prepared.get.warnings[0]

    editor.state.statusMessage = ""
    check editor.processFileResult(HandlerResult(kind: hrQuickRun), editor.activeBuffer)
    check "exited with 1" in editor.state.statusMessage

  test "An abort stops the QuickRun":
    let dir = testDir("quickrunabort")
    defer:
      removeDir(dir)
    let path = dir / "a.nim"
    var config = newEditorConfig()
    config.quickRun.saveBufferWhenQuickRun = true
    let editor = newEditor(config)
    editor.openInEditor(path, "echo 1\n")
    editor.activeBuffer.edit(@["echo 2"])
    editor.config.hooks.entries = @[writePre("false", onFail = hfaAbort)]

    let prepared = editor.prepareQuickRun(editor.activeBuffer)
    check prepared.isErr
    check "not written" in prepared.error
    check readFile(path) == "echo 1\n"

  test ":w says what failed below what it saved":
    let dir = testDir("report")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(dir / "a.txt", "a\n")
    editor.config.hooks.entries = @[writePre("false")]

    editor.processSaveResult(
      HandlerResult(kind: hrSave, saveFilename: none(string), forceSave: false),
      editor.activeBuffer,
    )
    check "Saved: " in editor.state.statusMessage
    check "exited with 1" in editor.state.statusMessage

  test ":w that fails still says what the commands did":
    when defined(posix):
      let dir = testDir("writefails")
      defer:
        setFilePermissions(dir, {fpUserRead, fpUserWrite, fpUserExec})
        removeDir(dir)
      let editor = newEditor(newEditorConfig())
      editor.openInEditor(dir / "a.txt", "a\n")
      editor.activeBuffer.edit(@["b"])
      editor.config.hooks.entries = @[writePre("false")]
      # No write permission on the directory: the temp-and-rename write fails.
      setFilePermissions(dir, {fpUserRead, fpUserExec})
      if getuid() != 0:
        let saved = editor.saveFile(editor.activeBuffer)
        check saved.isErr
        check "exited with 1" in saved.error

  test ":wqa that fails still says what the commands of the files written did":
    let dir = testDir("wqareport")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(dir / "a.txt", "old\n")
    editor.activeBuffer.edit(@["new"])
    discard editor.addBackground(dir / "b.txt", "old")
    editor.config.hooks.entries = @[
      writePre("false", filter = r"a\.txt$"),
      writePre("false", onFail = hfaAbort, filter = r"b\.txt$"),
    ]

    check editor.processSaveAllAndQuitResult(HandlerResult(kind: hrSaveAllAndQuit))
    check readFile(dir / "a.txt") == "new\n"
    check "Save failed" in editor.state.statusMessage
    check "exited with 1" in editor.state.statusMessage.splitLines[^1]
    check editor.state.statusMessage.splitLines.len == 2

  test "A command silent on stderr is quoted from what it printed":
    let dir = testDir("stdoutreason")
    defer:
      removeDir(dir)
    let editor = newEditor(newEditorConfig())
    editor.openInEditor(dir / "a.txt", "a\n")
    editor.config.hooks.entries =
      @[writePre("sh -c 'echo; echo \"parse error at 1:1\"; exit 2'")]

    let saved = editor.saveFile(editor.activeBuffer)
    check saved.isOk
    check saved.get.warnings.len == 1
    check "exited with 2: parse error at 1:1" in saved.get.warnings[0]
