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
import ../src/moepkg/[editor_buffers, editor_file, editor_navigation]

let cacheHome = getTempDir() / "moe_test_editor_persist"
putEnv("XDG_CACHE_HOME", cacheHome)

proc createTestEditor(bookmarks = true): Editor =
  var config = newEditorConfig()
  config.persist.bookmarks = bookmarks
  config.persist.search = false
  config.persist.commandHistory = false
  config.persist.cursorPosition = false
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
