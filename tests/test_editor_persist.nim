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

## Per-file state saved at exit is merged into the cache file as it is then:
## entries this session did not restore stay as they are on disk.

import std/[unittest, json, options, os, strutils, tables]

import pkg/results

import ../src/moepkg/[editor, config, config_loader, persist]
import ../src/moepkg/[editor_buffers, editor_file, editor_navigation, editor_window]
import ../src/moepkg/[filer, viewer_mode, window_manager]
import ../src/moepkg/[editor_persist, search_utils, primitives]
import ../src/moepkg/buffer/search
import ../src/moepkg/command_handlers/result_processor

let cacheHome = getTempDir() / "moe_test_editor_persist"
putEnv("XDG_CACHE_HOME", cacheHome)

proc createTestEditor(bookmarks = true, cursorPosition = false): Editor =
  var config = newEditorConfig()
  config.persist.bookmarks = bookmarks
  config.persist.search = false
  config.persist.commandHistory = false
  config.persist.cursorPosition = cursorPosition
  result = newEditor(config, newValidationResult())
  result.state.showGitDiff = false

proc writeTestFile(name: string): string =
  result = cacheHome / name
  writeFile(result, "a\nb\nc\nd\n")

proc savedBookmarks(): Table[string, seq[int]] =
  let loaded = loadBookmarks()
  check loaded.isOk
  loaded.valueOr(initTable[string, seq[int]]())

suite "bookmark persistence":
  setup:
    removeDir(cacheHome)
    createDir(cacheHome)

  teardown:
    removeDir(cacheHome)

  test "Saving keeps bookmarks of files not opened this session":
    check updateBookmarks({"/elsewhere/a.nim": @[3]}.toTable).isOk
    let e = createTestEditor()
    let path = writeTestFile("opened.txt")
    let opened = e.openFileInActiveWindow(path)
    check opened.isOk
    opened.get.bookmarks = @[1]

    e.savePersistData()

    let saved = savedBookmarks()
    check saved.getOrDefault("/elsewhere/a.nim") == @[3]
    check saved.getOrDefault(path) == @[1]

  test "Saving without any bookmarked buffer keeps the file":
    check updateBookmarks({"/elsewhere/a.nim": @[3]}.toTable).isOk
    let e = createTestEditor()

    e.savePersistData()

    check savedBookmarks().getOrDefault("/elsewhere/a.nim") == @[3]

  test "Clearing an open file's bookmarks drops only its entry":
    let path = writeTestFile("cleared.txt")
    check updateBookmarks({"/elsewhere/a.nim": @[3], path: @[2]}.toTable).isOk
    let e = createTestEditor()
    let opened = e.openFileInActiveWindow(path)
    check opened.isOk
    check opened.get.bookmarks == @[2]
    opened.get.bookmarks = @[]

    e.savePersistData()

    let saved = savedBookmarks()
    check path notin saved
    check saved.getOrDefault("/elsewhere/a.nim") == @[3]

  test "Closing a buffer keeps the bookmarks it had":
    let path = writeTestFile("closed.txt")
    check updateBookmarks({path: @[2]}.toTable).isOk
    let e = createTestEditor()
    let opened = e.openFileInActiveWindow(path)
    check opened.isOk
    opened.get.bookmarks = @[0, 3]

    check e.deleteBufferById(opened.get.id).isOk
    let reopened = e.openFileInActiveWindow(path)
    check reopened.isOk
    check reopened.get.bookmarks == @[0, 3]

    check e.deleteBufferById(reopened.get.id).isOk
    e.savePersistData()

    check savedBookmarks().getOrDefault(path) == @[0, 3]

  test "Entries another session saved after startup survive":
    let path = writeTestFile("mine.txt")
    let e = createTestEditor()
    let opened = e.openFileInActiveWindow(path)
    check opened.isOk
    opened.get.bookmarks = @[1]
    # Another session exits after this one read the file.
    check updateBookmarks({"/elsewhere/b.nim": @[5]}.toTable).isOk

    e.savePersistData()

    let saved = savedBookmarks()
    check saved.getOrDefault("/elsewhere/b.nim") == @[5]
    check saved.getOrDefault(path) == @[1]

  test "An unreadable file is left alone instead of being replaced":
    let path = writeTestFile("unreadable.txt")
    let bmPath = getBookmarksPath().get.string
    createDir(bmPath.parentDir)
    writeFile(bmPath, "not json {{{")
    let e = createTestEditor()
    let opened = e.openFileInActiveWindow(path)
    check opened.isOk
    opened.get.bookmarks = @[1]

    e.savePersistData()

    check readFile(bmPath) == "not json {{{"

  test "An unreadable file is reported once when a file opens":
    let first = writeTestFile("first.txt")
    let second = writeTestFile("second.txt")
    let bmPath = getBookmarksPath().get.string
    createDir(bmPath.parentDir)
    writeFile(bmPath, "not json {{{")
    let e = createTestEditor()

    check e.openFileInActiveWindow(first).isOk
    check "Cannot read bookmarks" in e.state.statusMessage

    e.state.statusMessage = ""
    check e.openFileInActiveWindow(second).isOk
    check "Cannot read" notin e.state.statusMessage

  test "Turning persistence on does not erase a file opened while it was off":
    let path = writeTestFile("late.txt")
    check updateBookmarks({path: @[2]}.toTable).isOk
    let e = createTestEditor(bookmarks = false)
    let opened = e.openFileInActiveWindow(path)
    check opened.isOk
    check opened.get.bookmarks.len == 0

    e.config.persist.bookmarks = true
    e.savePersistData()

    check savedBookmarks().getOrDefault(path) == @[2]

  test "A differently spelled path finds the same entry":
    let path = writeTestFile("spelled.txt")
    check updateBookmarks({cacheHome / "." / "spelled.txt": @[3]}.toTable).isOk
    let e = createTestEditor()

    let opened = e.openFileInActiveWindow(path)

    check opened.isOk
    check opened.get.bookmarks == @[3]

suite "cursor position persistence":
  setup:
    removeDir(cacheHome)
    createDir(cacheHome)

  teardown:
    removeDir(cacheHome)

  test "Saving keeps positions of files not opened this session":
    let other = CursorPositionEntry(line: 7, column: 2)
    check updateCursorPositions({"/elsewhere/a.nim": other}.toTable).isOk
    var config = newEditorConfig()
    config.persist.bookmarks = false
    config.persist.search = false
    config.persist.commandHistory = false
    let e = newEditor(config, newValidationResult())
    e.state.showGitDiff = false
    let path = writeTestFile("cursor.txt")
    check e.loadFile(path).isOk
    e.cursor = BufferPosition(line: 2, column: 0)

    e.savePersistData()

    let saved = loadCursorPositions()
    check saved.isOk
    check saved.get.getOrDefault("/elsewhere/a.nim") == other
    check saved.get.getOrDefault(path) == CursorPositionEntry(line: 2, column: 0)

suite "persistence across sessions":
  setup:
    removeDir(cacheHome)
    createDir(cacheHome)

  teardown:
    removeDir(cacheHome)

  test "Only opening a file does not erase bookmarks another session saved":
    let path = writeTestFile("shared.txt")
    let e = createTestEditor()
    check e.openFileInActiveWindow(path).isOk
    check updateBookmarks({path: @[1, 3]}.toTable).isOk

    e.savePersistData()

    check savedBookmarks().getOrDefault(path) == @[1, 3]

  test "Unchanged restored bookmarks do not overwrite a newer save":
    let path = writeTestFile("shared2.txt")
    check updateBookmarks({path: @[1]}.toTable).isOk
    let e = createTestEditor()
    let opened = e.openFileInActiveWindow(path)
    check opened.isOk
    check opened.get.bookmarks == @[1]
    check updateBookmarks({path: @[1, 2]}.toTable).isOk

    e.savePersistData()

    check savedBookmarks().getOrDefault(path) == @[1, 2]

  test "Bookmarks of a buffer named by :w are saved":
    let e = createTestEditor()
    e.activeBuffer.bookmarks = @[0]
    let path = cacheHome / "named.txt"
    check e.saveFile(e.activeBuffer, some(path)).isOk

    e.savePersistData()

    check savedBookmarks().getOrDefault(path) == @[0]

  test "A file opened later sees what another session saved meanwhile":
    let first = writeTestFile("first.txt")
    let later = writeTestFile("later.txt")
    let e = createTestEditor()
    check e.openFileInActiveWindow(first).isOk
    check updateBookmarks({later: @[2]}.toTable).isOk

    let opened = e.openFileInActiveWindow(later)

    check opened.isOk
    check opened.get.bookmarks == @[2]

  test "Saved bookmarks are restored sorted, unique and within the file":
    let path = writeTestFile("messy.txt")
    let bmPath = getBookmarksPath().get.string
    createDir(bmPath.parentDir)
    writeFile(bmPath, "{\"" & path & "\": [3, 1, 3, 40]}")
    let e = createTestEditor()

    let opened = e.openFileInActiveWindow(path)

    check opened.isOk
    check opened.get.bookmarks == @[1, 3]

  test "A negative saved cursor line does not crash opening the file":
    var config = newEditorConfig()
    config.persist.bookmarks = false
    config.persist.search = false
    config.persist.commandHistory = false
    let e = newEditor(config, newValidationResult())
    e.state.showGitDiff = false
    let path = writeTestFile("negative.txt")
    let posPath = getCursorPositionsPath().get.string
    createDir(posPath.parentDir)
    writeFile(posPath, "{\"" & path & "\": {\"line\": -3, \"column\": -1}}")

    check e.loadFile(path).isOk
    check e.cursor == BufferPosition(line: 0, column: 0)

  test "An unmoved restored cursor does not overwrite a newer save":
    var config = newEditorConfig()
    config.persist.bookmarks = false
    config.persist.search = false
    config.persist.commandHistory = false
    let e = newEditor(config, newValidationResult())
    e.state.showGitDiff = false
    let path = writeTestFile("unmoved.txt")
    check updateCursorPositions({path: CursorPositionEntry(line: 1, column: 0)}.toTable).isOk
    check e.loadFile(path).isOk
    check e.cursor == BufferPosition(line: 1, column: 0)
    let newer = CursorPositionEntry(line: 3, column: 0)
    check updateCursorPositions({path: newer}.toTable).isOk

    e.savePersistData()

    check loadCursorPositions().get.getOrDefault(path) == newer

  test "An unreadable cursor position file is reported when a file opens":
    var config = newEditorConfig()
    config.persist.bookmarks = false
    config.persist.search = false
    config.persist.commandHistory = false
    let e = newEditor(config, newValidationResult())
    e.state.showGitDiff = false
    let path = writeTestFile("unreadable_pos.txt")
    let posPath = getCursorPositionsPath().get.string
    createDir(posPath.parentDir)
    writeFile(posPath, "null")

    check e.loadFile(path).isOk
    check "Cannot read cursor positions" in e.state.statusMessage

  test "Saving keeps the most recent files and those opened this session":
    let path = writeTestFile("recent.txt")
    # Written by a version without the limit; the opened file comes last.
    var old = newJObject()
    for i in 0 ..< MaxRecordedFiles + 20:
      old["/old/" & $i & ".nim"] = %[i]
    old[path] = %[2]
    let bmPath = getBookmarksPath().get.string
    createDir(bmPath.parentDir)
    writeFile(bmPath, $old)
    let e = createTestEditor()
    check e.openFileInActiveWindow(path).isOk
    let changed = writeTestFile("changed.txt")
    let opened = e.openFileInActiveWindow(changed)
    check opened.isOk
    opened.get.bookmarks = @[1]

    e.savePersistData()

    let saved = savedBookmarks()
    check saved.len == MaxRecordedFiles
    check saved.getOrDefault(changed) == @[1]
    check saved.getOrDefault(path) == @[2]
    check "/old/0.nim" in saved
    check "/old/" & $(MaxRecordedFiles + 19) & ".nim" notin saved

proc cursorEditor(): Editor =
  createTestEditor(bookmarks = false, cursorPosition = true)

proc writeLines(name: string): string =
  result = cacheHome / name
  writeFile(result, "alpha\nbravo\ncharlie\ndelta\necho\n")

proc savedCursor(path: string): CursorPositionEntry =
  let loaded = loadCursorPositions()
  check loaded.isOk
  check path in loaded.get
  loaded.get.getOrDefault(path)

proc saveCursor(path: string, line, column: int) =
  check updateCursorPositions(
    {path: CursorPositionEntry(line: line, column: column)}.toTable
  ).isOk

proc cursorIs(e: Editor, line, column: int): bool =
  e.cursor == BufferPosition(line: line, column: column)

proc focus(e: Editor, win: EditorWindow) =
  for i, candidate in e.windowManager.windows:
    if candidate == win:
      e.windowManager.activateWindow(i)
      e.syncActiveWindow()

proc splitFiler(e: Editor): bool =
  let filerState = newFilerState(cacheHome)
  e.enterViewerMode(
    EditorMode.Filer,
    ModeState(kind: mskFiler, filer: filerState),
    filerState.createFilerTextBuffer(false),
    vpVSplit,
  ).isOk

suite "cursor position persistence":
  setup:
    removeDir(cacheHome)
    createDir(cacheHome)

  teardown:
    removeDir(cacheHome)

  test "Saving records every file a window left, not only the active one":
    let e = cursorEditor()
    let first = writeLines("first.txt")
    let second = writeLines("second.txt")
    check e.editFile(first).isOk
    e.cursor = BufferPosition(line: 3, column: 2)
    check e.editFile(second).isOk
    e.cursor = BufferPosition(line: 1, column: 1)

    e.savePersistData()

    check savedCursor(first) == CursorPositionEntry(line: 3, column: 2)
    check savedCursor(second) == CursorPositionEntry(line: 1, column: 1)

  test "Saving under a viewer records the file below it":
    let e = cursorEditor()
    let path = writeLines("covered.txt")
    check e.editFile(path).isOk
    e.cursor = BufferPosition(line: 2, column: 3)
    let filerState = newFilerState(cacheHome)
    check e.enterViewerMode(
      EditorMode.Filer,
      ModeState(kind: mskFiler, filer: filerState),
      filerState.createFilerTextBuffer(false),
      vpInPlace,
    ).isOk

    e.savePersistData()

    check savedCursor(path) == CursorPositionEntry(line: 2, column: 3)

  test "A file opened in the background keeps its record":
    let path = writeLines("background.txt")
    saveCursor(path, 4, 1)
    let e = cursorEditor()
    check e.openFileInBackground(path).isOk

    e.savePersistData()

    check savedCursor(path) == CursorPositionEntry(line: 4, column: 1)

  test "A file opened and left alone keeps its record":
    let path = writeLines("untouched.txt")
    let other = writeLines("other.txt")
    saveCursor(path, 4, 1)
    let e = cursorEditor()
    check e.editFile(path).isOk
    check e.editFile(other).isOk

    e.savePersistData()

    check savedCursor(path) == CursorPositionEntry(line: 4, column: 1)

  test "A file read in the background opens where the last session left it":
    let path = writeLines("read_first.txt")
    saveCursor(path, 3, 2)
    let e = cursorEditor()
    check e.openFileInBackground(path).isOk

    check e.editFile(path).isOk

    check e.cursorIs(3, 2)

  test "Showing one file leaves the position of another":
    let first = writeLines("shown_first.txt")
    let second = writeLines("shown_second.txt")
    saveCursor(first, 3, 2)
    saveCursor(second, 2, 1)
    let e = cursorEditor()
    check e.openFileInBackground(first).isOk
    check e.openFileInBackground(second).isOk
    check e.editFile(first).isOk

    check e.editFile(second).isOk

    check e.cursorIs(2, 1)

  test "A split viewer outlasting its window saves where that window left":
    let e = cursorEditor()
    let path = writeLines("outlasted.txt")
    check e.editFile(path).isOk
    e.cursor = BufferPosition(line: 1, column: 0)
    let origin = e.activeWindow
    check e.splitFiler()
    let viewer = e.activeWindow
    e.focus(origin)
    e.cursor = BufferPosition(line: 4, column: 0)
    check not e.closeWindow()
    e.focus(viewer)

    e.savePersistData()

    check savedCursor(path).line == 4

  test "Closing a split viewer does not bury where its window left":
    let e = cursorEditor()
    let path = writeLines("buried.txt")
    let other = writeLines("buried_other.txt")
    check e.editFile(path).isOk
    e.cursor = BufferPosition(line: 1, column: 0)
    let origin = e.activeWindow
    check e.splitFiler()
    let viewer = e.activeWindow
    e.focus(origin)
    e.cursor = BufferPosition(line: 4, column: 0)
    check e.editFile(other).isOk
    e.focus(viewer)
    check not e.closeWindow()

    e.savePersistData()

    check savedCursor(path).line == 4

  test "Saving from a split viewer records the window it split from":
    let e = cursorEditor()
    let path = writeLines("split_viewer.txt")
    check e.editFile(path).isOk
    e.cursor = BufferPosition(line: 1, column: 0)
    let origin = e.activeWindow
    check e.splitFiler()
    let viewer = e.activeWindow
    e.focus(origin)
    e.cursor = BufferPosition(line: 4, column: 0)
    e.focus(viewer)

    e.savePersistData()

    check savedCursor(path).line == 4

  test "Closing a window keeps the newer line a closed window left":
    let e = cursorEditor()
    let path = writeLines("closed.txt")
    let other = writeLines("other.txt")
    check e.editFile(path).isOk
    let first = e.activeWindow
    check e.vsplit().isOk
    let older = e.activeWindow
    check e.vsplit().isOk
    let newer = e.activeWindow
    e.focus(first)
    check e.editFile(other).isOk
    e.focus(older)
    e.cursor = BufferPosition(line: 1, column: 0)
    check e.editFile(other).isOk
    e.focus(newer)
    e.cursor = BufferPosition(line: 4, column: 0)
    check e.editFile(other).isOk
    check not e.closeWindow()
    e.focus(older)
    check not e.closeWindow()

    e.savePersistData()

    check savedCursor(path).line == 4

  test "Only the first window takes the position of the last session":
    let path = writeLines("taken.txt")
    let other = writeLines("taken_other.txt")
    saveCursor(path, 3, 2)
    let e = cursorEditor()
    check e.editFile(path).isOk
    e.cursor = BufferPosition(line: 1, column: 0)
    check e.vsplit(some(other)).isOk

    check e.editFile(path).isOk

    check e.cursorIs(0, 0)

  test "The startup file is the first window as any other":
    let path = writeLines("startup.txt")
    let other = writeLines("startup_other.txt")
    saveCursor(path, 3, 2)
    let e = cursorEditor()
    check e.loadFile(path).isOk
    check e.cursorIs(3, 2)
    e.cursor = BufferPosition(line: 1, column: 0)
    check e.vsplit(some(other)).isOk

    check e.editFile(path).isOk

    check e.cursorIs(0, 0)

  test ":e opens a file where the last session left it":
    let path = writeLines("reopened.txt")
    saveCursor(path, 3, 2)
    let e = cursorEditor()

    check e.editFile(path).isOk

    check e.cursorIs(3, 2)

  test "A split opens a file where the last session left it":
    let path = writeLines("split.txt")
    saveCursor(path, 2, 4)
    let e = cursorEditor()

    check e.vsplit(some(path)).isOk

    check e.cursorIs(2, 4)

  test "A recorded position past the end lands on the last line":
    let path = writeLines("shrunk.txt")
    saveCursor(path, 40, 40)
    let e = cursorEditor()

    check e.editFile(path).isOk

    check e.cursorIs(4, 3)

  test "persist.cursorPosition off opens at the top":
    let path = writeLines("disabled.txt")
    saveCursor(path, 3, 2)
    let e = createTestEditor(bookmarks = false, cursorPosition = false)

    check e.editFile(path).isOk

    check e.cursorIs(0, 0)

  test "Coming back within a session keeps the line, not the column":
    let path = writeLines("back.txt")
    let other = writeLines("away.txt")
    saveCursor(path, 3, 2)
    let e = cursorEditor()
    check e.editFile(path).isOk
    check e.editFile(other).isOk

    check e.editFile(path).isOk

    check e.cursorIs(3, 0)

  test "A closed file opens again where it was":
    let path = writeLines("closed.txt")
    let other = writeLines("stays.txt")
    let e = cursorEditor()
    check e.editFile(other).isOk
    check e.editFile(path).isOk
    e.cursor = BufferPosition(line: 3, column: 2)

    check e.deleteBufferByArg(path).isOk
    check e.editFile(path).isOk

    check e.cursorIs(3, 2)

proc createSearchTestEditor(): Editor =
  ## An editor that persists the search state, as the application runs.
  var config = newEditorConfig()
  config.persist.bookmarks = false
  config.persist.search = true
  config.persist.commandHistory = false
  config.persist.cursorPosition = false
  result = newEditor(config, newValidationResult())
  result.state.showGitDiff = false

suite "last search persistence":
  setup:
    removeDir(cacheHome)
    createDir(cacheHome)

  teardown:
    removeDir(cacheHome)

  test "Saving keeps the last search":
    let e = createSearchTestEditor()
    e.state.input.search.last =
      SearchSpec(pattern: "Foo", match: smPlain, direction: Backward)

    e.savePersistData()

    let saved = loadLastSearch()
    check saved.isSome
    check saved.get.pattern == "Foo"
    check saved.get.match == smPlain

  test "Restoring brings back the last search":
    let e = createSearchTestEditor()
    e.state.input.search.last =
      SearchSpec(pattern: "Foo", match: smPlain, direction: Backward)
    e.savePersistData()

    let restored = createSearchTestEditor()
    check restored.state.input.search.last.pattern == ""
    restored.restoreLastSearch()
    # As Vim's viminfo, a new session searches forward whichever way it went.
    check restored.state.input.search.last ==
      SearchSpec(pattern: "Foo", match: smPlain, direction: Forward)
    # The first screen draws no matches, as Vim starts with 'hlsearch' off.
    check restored.state.input.search.hlsearchTempDisabled

  test "A restored search runs an empty :s pattern":
    let e = createSearchTestEditor()
    e.state.input.search.last =
      SearchSpec(pattern: "foo", match: smPlain, direction: Forward)
    e.savePersistData()

    let path = cacheHome / "restored.txt"
    writeFile(path, "foo bar\nfoo baz\n")
    let restored = createSearchTestEditor()
    restored.restoreLastSearch()
    check restored.openFileInActiveWindow(path).isOk
    restored.state.keyTyped = true

    check restored.executeCommandOverlay(":%s//new/g") == roContinue
    check restored.activeBuffer().getLine(0) == "new bar"
    check restored.activeBuffer().getLine(1) == "new baz"
    # An executed :s shows its matches again, as it does in a session.
    check not restored.state.input.search.hlsearchTempDisabled

  test "The history alone restores no last search":
    # It also holds :s patterns and searches given up, which never ran.
    let e = createSearchTestEditor()
    e.state.input.search.history = @["newest", "older"]

    e.restoreLastSearch()

    check e.state.input.search.last.pattern == ""
    check not e.state.input.search.hlsearchTempDisabled

  test "'persist.search' off neither saves nor restores":
    var config = newEditorConfig()
    config.persist.bookmarks = false
    config.persist.search = false
    config.persist.commandHistory = false
    config.persist.cursorPosition = false
    let e = newEditor(config, newValidationResult())
    e.state.showGitDiff = false
    e.state.input.search.last = SearchSpec(pattern: "Foo", match: smPlain)

    e.savePersistData()

    check loadLastSearch().isNone
    e.state.input.search.last = SearchSpec()
    e.state.input.search.history = @["foo"]
    e.restoreLastSearch()
    check e.state.input.search.last.pattern == ""
