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

## Tests for editor_lsp_rename.nim: the rename flow gives every file it touches
## a buffer, so a file the user never opened is edited inside a transaction and
## can be undone. Nothing reaches disk — the targets are left as modified
## buffers for the user to save.

import std/[unittest, os, options, tables, sequtils]
from std/strutils import contains

import pkg/results

import ../src/moepkg/[editor, config, config_loader, types, lsp_service]
import ../src/moepkg/buffer
import ../src/moepkg/lsp_integration
import ../src/moepkg/editor_lsp_rename {.all.}
import ../src/moepkg/lsp/protocol/types as lspTypes

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc editReplacingFirstWord(paths: openArray[string], newText: string): WorkspaceEdit =
  ## A WorkspaceEdit replacing columns 0..5 of line 0 in every given file.
  var changes = initTable[string, seq[TextEdit]]()
  for path in paths:
    changes[pathToUri(path)] =
      @[TextEdit(range: newRange(0, 0, 0, 5), newText: newText)]
  WorkspaceEdit(changes: some(changes), documentChanges: none(seq[TextDocumentEdit]))

proc orderedEditReplacingFirstWord(
    paths: openArray[string], newText: string
): WorkspaceEdit =
  ## Same edit through `documentChanges`, whose seq fixes the order in which
  ## the targets are opened (the `changes` table does not).
  var docEdits: seq[TextDocumentEdit] = @[]
  for path in paths:
    docEdits.add(
      TextDocumentEdit(
        textDocument: OptionalVersionedTextDocumentIdentifier(
          uri: pathToUri(path), version: some(1)
        ),
        edits: @[TextEdit(range: newRange(0, 0, 0, 5), newText: newText)],
      )
    )
  WorkspaceEdit(
    changes: none(Table[string, seq[TextEdit]]), documentChanges: some(docEdits)
  )

proc bufferForPath(e: Editor, path: string): TextBuffer =
  for buf in e.buffers:
    if buf.filePath.isSome and buf.filePath.get == path:
      return buf
  nil

suite "editor_lsp_rename - openRenameTargets":
  let tmpDir = getTempDir() / "moe_test_lsp_rename"

  setup:
    removeDir(tmpDir)
    createDir(tmpDir)

  teardown:
    removeDir(tmpDir)

  test "opens an unopened target as a buffer no window shows":
    let e = createTestEditor()
    let targetPath = tmpDir / "target.txt"
    writeFile(targetPath, "hello there")
    let bufferCountBefore = e.buffers.len

    let opened = e.openRenameTargets(editReplacingFirstWord([targetPath], "world"))

    check opened.isOk
    check opened.get.len == 1
    check e.buffers.len == bufferCountBefore + 1
    let buf = e.bufferForPath(targetPath)
    check buf != nil
    if buf != nil:
      check buf.id == opened.get[0]
      # No window shows it, so nothing on screen moved.
      check opened.get[0] notin e.activeWindow.bufferIds

  test "reports a target the user already had open as not opened here":
    let e = createTestEditor()
    let targetPath = tmpDir / "already_open.txt"
    writeFile(targetPath, "hello there")
    check e.openFileInBackground(targetPath).isOk
    let bufferCountBefore = e.buffers.len

    let opened = e.openRenameTargets(editReplacingFirstWord([targetPath], "world"))

    check opened.isOk
    # The buffer is reused, and its id is not reported: a buffer the user
    # already had must not be closed on their behalf if the rename fails.
    check opened.get.len == 0
    check e.buffers.len == bufferCountBefore

  test "opens nothing when a target cannot be loaded":
    let e = createTestEditor()
    let goodPath = tmpDir / "good.txt"
    writeFile(goodPath, "hello there")
    let badPath = tmpDir / "unreadable.txt"
    writeFile(badPath, "hello there")
    setFilePermissions(badPath, {fpUserWrite})
    var canRead = true
    try:
      discard readFile(badPath)
    except CatchableError:
      canRead = false
    if canRead:
      # Running as root: an unreadable file is still readable, so there is no
      # way to fail the load here.
      setFilePermissions(badPath, {fpUserRead, fpUserWrite})
      skip()
    else:
      let bufferCountBefore = e.buffers.len

      # The good file sorts first in the edit, so it is opened before the
      # failure and has to be closed again.
      let opened =
        e.openRenameTargets(orderedEditReplacingFirstWord([goodPath, badPath], "world"))

      check opened.isErr
      check "no edits applied" in opened.error
      # A rename that cannot touch every target must touch none.
      check e.buffers.len == bufferCountBefore
      check e.bufferForPath(goodPath) == nil
      check readFile(goodPath) == "hello there"
      setFilePermissions(badPath, {fpUserRead, fpUserWrite})

  test "opens nothing for an edit carrying file operations":
    let e = createTestEditor()
    let targetPath = tmpDir / "with_file_ops.txt"
    writeFile(targetPath, "hello there")
    var edit = editReplacingFirstWord([targetPath], "world")
    edit.resourceOperations = @["create"]
    let bufferCountBefore = e.buffers.len

    let opened = e.openRenameTargets(edit)

    check opened.isErr
    check e.buffers.len == bufferCountBefore

suite "editor_lsp_rename - a rename edits buffers and writes nothing":
  let tmpDir = getTempDir() / "moe_test_lsp_rename_undo"

  setup:
    removeDir(tmpDir)
    createDir(tmpDir)

  teardown:
    removeDir(tmpDir)

  test "the file is left modified in a buffer, not written, and undo reverts it":
    let e = createTestEditor()
    let targetPath = tmpDir / "renamed.txt"
    writeFile(targetPath, "hello there\nsecond line\n")
    let edit = editReplacingFirstWord([targetPath], "world")

    let opened = e.openRenameTargets(edit)
    check opened.isOk
    let applied = applyWorkspaceEdit(e.buffers, edit)
    check applied.isOk
    check applied.get.modifiedBufferIndexes.len == 1

    # The rename never touches the file: saving is the user's `:w`/`:wa`.
    check readFile(targetPath) == "hello there\nsecond line\n"

    let buf = e.bufferForPath(targetPath)
    check buf != nil
    if buf != nil:
      check buf.isModified
      check buf.getLine(0) == "world there"
      # The whole point: the file the user never opened has an undo history.
      check buf.undo().isOk
      check buf.getLine(0) == "hello there"

  test "a target the user already had open is left modified too":
    let e = createTestEditor()
    let targetPath = tmpDir / "user_opened.txt"
    writeFile(targetPath, "hello there\n")
    check e.openFileInBackground(targetPath).isOk
    let edit = editReplacingFirstWord([targetPath], "world")

    let opened = e.openRenameTargets(edit)
    check opened.isOk
    # A buffer the user already had is not reported as opened here, and is
    # treated no differently from one this flow opened.
    check opened.get.len == 0
    check applyWorkspaceEdit(e.buffers, edit).isOk

    let buf = e.bufferForPath(targetPath)
    check buf != nil
    if buf != nil:
      check buf.isModified
    check readFile(targetPath) == "hello there\n"

  test "several targets are all modified in buffers and all undoable":
    let e = createTestEditor()
    let paths = @[tmpDir / "one.txt", tmpDir / "two.txt", tmpDir / "three.txt"]
    for path in paths:
      writeFile(path, "hello there\n")
    let edit = editReplacingFirstWord(paths, "world")

    let opened = e.openRenameTargets(edit)
    check opened.isOk
    check opened.get.len == 3
    check applyWorkspaceEdit(e.buffers, edit).isOk

    check paths.allIt(readFile(it) == "hello there\n")
    check paths.allIt(e.bufferForPath(it).getLine(0) == "world there")

    for path in paths:
      let buf = e.bufferForPath(path)
      check buf != nil
      if buf != nil:
        check buf.undo().isOk
    check paths.allIt(e.bufferForPath(it).getLine(0) == "hello there")

  test "saveAllBuffers is what puts a renamed file on disk":
    # The Vim-shaped contract: the rename modifies buffers, `:wa` writes them.
    let e = createTestEditor()
    let targetPath = tmpDir / "written_by_wa.txt"
    writeFile(targetPath, "hello there\n")
    let edit = editReplacingFirstWord([targetPath], "world")

    check e.openRenameTargets(edit).isOk
    check applyWorkspaceEdit(e.buffers, edit).isOk
    check readFile(targetPath) == "hello there\n"

    let saveResult = e.saveAllBuffers()
    check saveResult.failures.len == 0
    check saveResult.skippedExternal.len == 0
    check readFile(targetPath) == "world there\n"

suite "editor_lsp_rename - closeRenameTargets":
  let tmpDir = getTempDir() / "moe_test_lsp_rename_close"

  setup:
    removeDir(tmpDir)
    createDir(tmpDir)

  teardown:
    removeDir(tmpDir)

  test "dropping the buffers opened here reverts a half-applied edit":
    let e = createTestEditor()
    let targetPath = tmpDir / "half_applied.txt"
    writeFile(targetPath, "hello there\n")
    let edit = editReplacingFirstWord([targetPath], "world")

    let opened = e.openRenameTargets(edit)
    check opened.isOk
    check applyWorkspaceEdit(e.buffers, edit).isOk
    let bufferCountBefore = e.buffers.len

    # Nothing was saved yet, so closing the buffer leaves the file as it was.
    e.closeRenameTargets(opened.get)

    check e.buffers.len == bufferCountBefore - 1
    check e.bufferForPath(targetPath) == nil
    check readFile(targetPath) == "hello there\n"
