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

import std/[monotimes, os, strutils, unicode, unittest]
from std/times import initDuration

import pkg/results

import ../src/moepkg/celina_backend
import
  ../src/moepkg/[
    editor, types, config, editor_frame, buffer, encoding, handler, key_bindings,
    job_lanes,
  ]
import ../src/moepkg/syntax/tokenizer
import ../src/moepkg/command_handlers/result_processor
import ../src/moepkg/picker/[layout, render, session]
import ../src/moepkg/picker/preview {.all.}
from vim_like_test_helper import keysOf

let dir = getTempDir() / ("moe_test_picker_preview_" & $getCurrentProcessId())

proc utf16le(s: string): string =
  for r in s.runes:
    var code = r.int
    if code >= 0x10000:
      code -= 0x10000
      for unit in [0xD800 + (code shr 10), 0xDC00 + (code and 0x3FF)]:
        result.add char(unit and 0xFF)
        result.add char(unit shr 8)
    else:
      result.add char(code and 0xFF)
      result.add char(code shr 8)

proc numbered(prefix: string, count: int): string =
  for i in 0 ..< count:
    result.add prefix & " " & $i & "\n"

proc newPreviewEditor(): Editor =
  createDir(dir)
  let config = newEditorConfig()
  config.theme.kind = tkDefault
  newEditor(config)

proc openFilePicker(e: Editor, paths: openArray[string]) =
  ## A picker over the active window listing `paths` as files to open.
  var items: seq[PickerItem]
  for path in paths:
    let name = path.extractFilename
    items.add PickerItem(
      key: name, display: name, target: PickerTarget(kind: ptkFile, path: path)
    )
  e.state.enterPickerOverlay(
    PickerSession(title: "Files", items: items, previews: true), "", e.activeWindow
  )
  e.state.picker.advancePicker("")

proc typeKeys(e: Editor, spec: string) =
  for k in keysOf(spec):
    check e.handleKeyCombo(k)

proc frame(e: Editor, width = 120, height = 40): Buffer =
  result = newBuffer(width, height)
  e.render(result)

proc settlePreview(e: Editor) =
  ## Let the selection rest on its item long enough to be read.
  let now = getMonoTime()
  e.advancePickerPreview(now, onScreen = true)
  e.advancePickerPreview(now + PreviewSettle, onScreen = true)

const ShiftDown = KeyCombo(isSpecial: true, special: skDown, modifiers: {kmShift})
const ShiftUp = KeyCombo(isSpecial: true, special: skUp, modifiers: {kmShift})

proc halfPreview(e: Editor): int =
  e.state.pickerScreenLayout(e.screenSize.width, e.screenSize.height).preview.height div
    2

proc row(screen: Buffer, y, x0, x1: int): string =
  for x in x0 ..< x1:
    result.add screen[x, y].symbol

suite "picker preview: cutting the start of a large file":
  test "UTF-8 ends at its last line ending":
    check cutAtLineEnd("ab\ncd\nef", CharacterEncoding.utf8) == "ab\ncd\n"

  test "Without a line ending, a character the end cuts is left out":
    check cutAtLineEnd("a\xC3", CharacterEncoding.utf8) == "a"
    check cutAtLineEnd("ab", CharacterEncoding.utf8) == "ab"

  test "UTF-16 ends at a line ending of its own unit":
    let head = utf16le("a\nb") & "\x00"
    check cutAtLineEnd(head, CharacterEncoding.utf16Le) == utf16le("a\n")

  test "UTF-16 does not take a newline byte across two units for one":
    # U+0A41 then U+4E00 is `41 0A 00 4E`: `0A 00` at an odd offset.
    let head = utf16le("ੁ一x")
    check cutAtLineEnd(head, CharacterEncoding.utf16Le) == head

  test "A high surrogate the end parts from its low one is left out":
    let head = utf16le("a😀")[0 ..< 4]
    check cutAtLineEnd(head, CharacterEncoding.utf16Le) == utf16le("a")

  test "UTF-16 with a byte order mark follows it":
    let head = "\xFF\xFE" & utf16le("a\nb")
    check cutAtLineEnd(head, CharacterEncoding.utf16) == "\xFF\xFE" & utf16le("a\n")

  test "UTF-32 big endian ends at a line ending of its own unit":
    let head = "\0\0\0a\0\0\0\n\0\0\0b\0\0"
    check cutAtLineEnd(head, CharacterEncoding.utf32Be) == "\0\0\0a\0\0\0\n"

  test "Bytes in no known encoding are kept as they are":
    check cutAtLineEnd("a\nb", CharacterEncoding.unknown) == "a\nb"

suite "picker preview: reading a file":
  setup:
    createDir(dir)
  teardown:
    removeDir(dir)

  test "A large file with no line ending is cut at a character, not read raw":
    let path = dir / "long.nim"
    # An odd start before two-byte characters puts the limit inside one.
    writeFile(path, "let x = \"" & "é".repeat(PreviewMaxBytes div 2) & "\"")
    let read = readPreview(path, newEditorConfig())
    check read.message == ""
    check read.cut
    check read.buffer != nil
    check read.buffer.allowsTextTransforms
    check read.buffer.language == SourceLanguage.langNim
    check read.buffer.getLine(0).startsWith("let x = \"éé")

  test "A large UTF-16 file with no byte order mark is cut on a line ending":
    # `Ø` (D8 00) is a lone surrogate read big endian, so the file reads as
    # UTF-16LE only, and as no UTF-8.
    let path = dir / "wide.txt"
    let text = numbered("Ø", 100_000)
    writeFile(path, utf16le(text))
    check utf16le(text).len > PreviewMaxBytes
    let read = readPreview(path, newEditorConfig())
    check read.message == ""
    check read.cut
    check read.buffer.encoding == CharacterEncoding.utf16Le
    check read.buffer.getLine(0) == "Ø 0"
    let last = read.buffer.getLine(read.buffer.len - 1)
    check last == "Ø " & $(read.buffer.len - 1)

  test "A small file is read whole":
    let path = dir / "small.txt"
    writeFile(path, "one\ntwo\n")
    let read = readPreview(path, newEditorConfig())
    check not read.cut
    check read.buffer.len == 2
    check read.buffer.getLine(1) == "two"

  test "A file read uses up no buffer number":
    let path = dir / "small.txt"
    writeFile(path, "one\n")
    let before = newTextBuffer()
    let read = readPreview(path, newEditorConfig())
    check read.buffer.id.int < 0
    check newTextBuffer().id.int == before.id.int + 1

  test "A file of the limit's size is not cut, one a byte larger is":
    let path = dir / "limit.txt"
    writeFile(path, "x".repeat(PreviewMaxBytes - 1) & "\n")
    check not readPreview(path, newEditorConfig()).cut
    writeFile(path, "x".repeat(PreviewMaxBytes) & "\n")
    check readPreview(path, newEditorConfig()).cut

  test "The start is read as the file is now, whatever size it had":
    let path = dir / "changed.txt"
    writeFile(path, "0123456789")
    check readHead(path, 100, size = 2) == "0123456789"
    check readHead(path, 100, size = 50) == "0123456789"
    check readHead(path, 4, size = 50) == "0123"

  test "A directory, a missing file and a binary file show why":
    check readPreview(dir, newEditorConfig()).message == "A directory"
    check readPreview(dir / "none", newEditorConfig()).message == "No such file"
    writeFile(dir / "bin", "a\0b")
    let binary = readPreview(dir / "bin", newEditorConfig())
    check binary.message == "A binary file"
    check binary.buffer.isNil

  when defined(posix):
    test "A pipe is not opened, which would wait for a writer":
      let path = dir / "fifo"
      check execShellCmd("mkfifo " & quoteShell(path)) == 0
      check readPreview(path, newEditorConfig()).message == "Not a regular file"

  test "The colors are those of the file opened":
    # The reserved word needs the config applied after the load.
    let path = dir / "colors.nim"
    writeFile(path, "proc f() = discard # TODO: x\n".repeat(50))
    let e = newPreviewEditor()
    let read = readPreview(path, e.config)
    let opened = e.loadOrCreateBuffer(path).get
    for b in [read.buffer, opened]:
      var rounds = 0
      while b.advanceUndrawnHighlight(10_000) > 0 and rounds < 100:
        inc rounds
    check read.buffer.highlight.colorSegments == opened.highlight.colorSegments

suite "picker preview: in the picker":
  setup:
    createDir(dir)
  teardown:
    removeDir(dir)

  test "A file is read once the selection rests on it":
    let e = newPreviewEditor()
    let a = dir / "a.txt"
    writeFile(a, numbered("a", 3))
    e.openFilePicker([a])
    let now = getMonoTime()
    e.advancePickerPreview(now, onScreen = true)
    check e.state.picker.preview.reads.len == 0
    check e.pickerPreviewView.buffer.isNil
    check e.pickerPreviewView.title == "Preview"
    e.advancePickerPreview(now + PreviewSettle, onScreen = true)
    check e.state.picker.preview.reads.len == 1
    check e.pickerPreviewView.buffer.getLine(0) == "a 0"

  test "A file read for the preview is no buffer of the editor and runs no hook":
    let e = newPreviewEditor()
    e.config.hooks.entries =
      @[HookEntry(event: heBufReadPost, command: "true", timeout: 5)]
    let a = dir / "a.txt"
    writeFile(a, "a\n")
    let buffers = e.buffers.len
    e.openFilePicker([a])
    e.settlePreview()
    check e.pickerPreviewView.buffer != nil
    check e.buffers.len == buffers
    for job in e.jobLanes.jobs:
      check " hook" notin job.label

  test "A file a buffer holds shows the buffer, edits and all":
    let e = newPreviewEditor()
    let a = dir / "a.txt"
    writeFile(a, "on disk\n")
    check e.executeCommandOverlay(":e " & a) == roContinue
    check e.activeBuffer.replaceLine(0, "edited").isOk
    e.openFilePicker([a])
    e.settlePreview()
    check e.state.picker.preview.reads.len == 0
    check e.pickerPreviewView.buffer.id == e.activeBuffer.id
    check e.pickerPreviewView.buffer.getLine(0) == "edited"

  test "A file changed on disk is read again when the selection comes back":
    let e = newPreviewEditor()
    let (a, b) = (dir / "a.txt", dir / "b.txt")
    writeFile(a, "first\n")
    writeFile(b, "b\n")
    e.openFilePicker([a, b])
    e.settlePreview()
    check e.pickerPreviewView.buffer.getLine(0) == "first"
    writeFile(a, "second, longer\n")
    e.typeKeys("<C-n>")
    e.settlePreview()
    e.typeKeys("<C-p>")
    e.settlePreview()
    check e.pickerPreviewView.buffer.getLine(0) == "second, longer"

  test "A scroll typed with the move in one input scrolls the item moved to":
    let e = newPreviewEditor()
    let (a, b) = (dir / "a.txt", dir / "b.txt")
    writeFile(a, numbered("a", 100))
    writeFile(b, numbered("b", 100))
    e.openFilePicker([a, b])
    discard e.frame()
    e.typeKeys("<C-n>")
    check e.handleKeyCombo(ShiftDown)
    e.settlePreview()
    let view = e.pickerPreviewView
    check view.buffer.getLine(0) == "b 0"
    check e.halfPreview > 0
    check view.topLine == e.halfPreview
    check e.handleKeyCombo(ShiftUp)
    check e.pickerPreviewView.topLine == 0

  test "An item moved back to starts at the top":
    let e = newPreviewEditor()
    let (a, b) = (dir / "a.txt", dir / "b.txt")
    writeFile(a, numbered("a", 100))
    writeFile(b, numbered("b", 100))
    e.openFilePicker([a, b])
    discard e.frame()
    e.settlePreview()
    check e.handleKeyCombo(ShiftDown)
    check e.pickerPreviewView.topLine > 0
    e.typeKeys("<C-n><C-p>")
    e.settlePreview()
    check e.pickerPreviewView.topLine == 0

  test "A query that moves the selection off an item drops its scroll":
    let e = newPreviewEditor()
    let (a, b) = (dir / "a.txt", dir / "b.txt")
    writeFile(a, numbered("a", 100))
    writeFile(b, numbered("b", 100))
    e.openFilePicker([a, b])
    discard e.frame()
    e.settlePreview()
    check e.handleKeyCombo(ShiftDown)
    let scrolled = e.pickerPreviewView.topLine
    check scrolled > 0
    # A query that keeps the selection on the item keeps the scroll.
    e.typeKeys("a")
    e.state.picker.advancePicker(e.state.input.line.text)
    e.settlePreview()
    check e.pickerPreviewView.topLine == scrolled
    e.typeKeys("<Backspace>b")
    e.state.picker.advancePicker(e.state.input.line.text)
    e.settlePreview()
    check e.pickerPreviewView.buffer.getLine(0) == "b 0"
    e.typeKeys("<Backspace>")
    e.state.picker.advancePicker(e.state.input.line.text)
    e.settlePreview()
    check e.pickerPreviewView.buffer.getLine(0) == "a 0"
    check e.pickerPreviewView.topLine == 0

  test "Nothing is read while the screen has no room for the preview":
    let e = newPreviewEditor()
    let a = dir / "a.txt"
    writeFile(a, "a\n")
    e.openFilePicker([a])
    let now = getMonoTime()
    e.advancePickerPreview(now, onScreen = false)
    e.advancePickerPreview(now + PreviewSettle, onScreen = false)
    check e.state.picker.preview.reads.len == 0
    e.advancePickerPreview(now + PreviewSettle, onScreen = true)
    e.advancePickerPreview(now + PreviewSettle + PreviewSettle, onScreen = true)
    check e.state.picker.preview.reads.len == 1

  test "Shift-Up recalls the history in a picker with nothing to preview":
    let e = newPreviewEditor()
    e.state.input.pickerHistory = @["older"]
    e.typeKeys(":picker<Enter>")
    check not e.state.picker.previews
    check e.handleKeyCombo(ShiftUp)
    check e.state.input.line.text == "older"

  test "Shift-Up scrolls the preview, not the history, in a picker with one":
    let e = newPreviewEditor()
    e.state.input.pickerHistory = @["older"]
    let a = dir / "a.txt"
    writeFile(a, numbered("a", 100))
    e.openFilePicker([a])
    discard e.frame()
    e.settlePreview()
    check e.handleKeyCombo(ShiftUp)
    check e.state.input.line.text == ""

  test "A long line draws the cells the row shows, tabs and all":
    let e = newPreviewEditor()
    let a = dir / "long.txt"
    writeFile(a, "\tab" & "x".repeat(500_000) & "\n")
    e.openFilePicker([a])
    discard e.frame()
    e.settlePreview()
    let screen = e.frame()
    let p = e.state.pickerScreenLayout(120, 40).preview
    let shown = screen.row(p.y, p.x, p.x + p.width)
    check shown.startsWith(" ".repeat(1 + e.tabStop) & "abxxx")
    check shown.len == p.width

  test "Scrolling stops with the last line at the top":
    let e = newPreviewEditor()
    let a = dir / "a.txt"
    writeFile(a, numbered("a", 5))
    e.openFilePicker([a])
    discard e.frame()
    e.settlePreview()
    for _ in 0 ..< 10:
      check e.handleKeyCombo(ShiftDown)
    check e.pickerPreviewView.topLine == 4
    check e.handleKeyCombo(ShiftUp)
    check e.pickerPreviewView.topLine == max(0, 4 - e.halfPreview)

  test "The preview draws the file's lines and its title":
    let e = newPreviewEditor()
    let a = dir / "a.txt"
    writeFile(a, numbered("line", 3))
    e.openFilePicker([a])
    discard e.frame()
    e.settlePreview()
    let screen = e.frame()
    let layout = e.state.pickerScreenLayout(120, 40)
    check layout.previewBeside
    let p = layout.preview
    check screen.row(p.y, p.x, p.x + p.width).strip == "line 0"
    check screen.row(p.y + 2, p.x, p.x + p.width).strip == "line 2"
    check " Preview " in screen.row(layout.frame.y, p.x, p.x + p.width)

  test "A closed picker keeps no file read for it, and a resume reads again":
    let e = newPreviewEditor()
    let a = dir / "a.txt"
    writeFile(a, "a\n")
    e.openFilePicker([a])
    e.settlePreview()
    check e.state.picker.preview.reads.len == 1
    e.typeKeys("<Esc>")
    check not e.state.isPickerOverlay
    check e.state.lastPicker.preview.reads.len == 0
    e.typeKeys(":picker resume<Enter>")
    check e.state.isPickerOverlay
    e.settlePreview()
    check e.pickerPreviewView.buffer.getLine(0) == "a"

  test "A resume with nothing selected shows nothing of the last subject":
    let e = newPreviewEditor()
    let a = dir / "a.txt"
    writeFile(a, "a\n")
    e.openFilePicker([a])
    e.settlePreview()
    check e.pickerPreviewView.title == "Preview"
    # Closed with a query that matches nothing before a frame took it.
    e.typeKeys("zzz<C-c>")
    check not e.state.isPickerOverlay
    e.typeKeys(":picker resume<Enter>")
    check e.state.isPickerOverlay
    e.state.picker.advancePicker(e.state.input.line.text)
    check e.state.picker.selectedItem.isNone
    e.settlePreview()
    check e.pickerPreviewView.title == ""
    check e.pickerPreviewView.buffer.isNil

  test "A frame reads the file once the selection rests, if the screen has room":
    let e = newPreviewEditor()
    let a = dir / "a.txt"
    writeFile(a, "a\n")
    e.openFilePicker([a])
    check e.state.pickerScreenLayout(80, 16).preview.height == 0
    for _ in 0 ..< 2:
      discard e.frame(80, 16)
      e.state.picker.preview.since = getMonoTime() - PreviewSettle
    check e.state.picker.preview.reads.len == 0
    discard e.frame()
    check e.state.picker.preview.reads.len == 0
    e.state.picker.preview.since = getMonoTime() - PreviewSettle
    discard e.frame()
    check e.state.picker.preview.reads.len == 1
    check e.pickerPreviewView.buffer.getLine(0) == "a"

  test "An item gone over before the selection rests is not read":
    let e = newPreviewEditor()
    let (a, b) = (dir / "a.txt", dir / "b.txt")
    writeFile(a, "a\n")
    writeFile(b, "b\n")
    e.openFilePicker([a, b])
    let start = getMonoTime()
    e.advancePickerPreview(start, onScreen = true)
    e.typeKeys("<C-n>")
    # The wait starts again on the item moved to.
    let moved = start + initDuration(milliseconds = 40)
    e.advancePickerPreview(moved, onScreen = true)
    e.advancePickerPreview(start + PreviewSettle, onScreen = true)
    check e.state.picker.preview.reads.len == 0
    e.advancePickerPreview(moved + PreviewSettle, onScreen = true)
    check e.state.picker.preview.reads.len == 1
    check e.state.picker.preview.reads[0].path == b

  test "A file a buffer came to hold while closed shows the buffer on a resume":
    let e = newPreviewEditor()
    let a = dir / "a.txt"
    writeFile(a, "on disk\n")
    e.openFilePicker([a])
    e.settlePreview()
    check e.pickerPreviewView.buffer.getLine(0) == "on disk"
    e.typeKeys("<C-c>")
    check not e.state.isPickerOverlay
    check e.executeCommandOverlay(":e " & a) == roContinue
    check e.activeBuffer.replaceLine(0, "edited").isOk
    e.typeKeys(":picker resume<Enter>")
    check e.state.isPickerOverlay
    e.settlePreview()
    require e.pickerPreviewView.buffer != nil
    check e.pickerPreviewView.buffer.id == e.activeBuffer.id
    check e.pickerPreviewView.buffer.getLine(0) == "edited"

  test "The buffers picker shows a buffer, and why once it is gone":
    let e = newPreviewEditor()
    let (a, b) = (dir / "a.txt", dir / "b.txt")
    writeFile(a, "a\n")
    writeFile(b, "b\n")
    check e.executeCommandOverlay(":e " & a) == roContinue
    let aId = e.activeBuffer.id
    check e.executeCommandOverlay(":e " & b) == roContinue
    e.typeKeys(":picker buffers<Enter>")
    check e.state.isPickerOverlay
    e.state.picker.advancePicker("")
    var row = 0
    while e.state.picker.selectedItem.get.target.buffer != aId:
      e.typeKeys("<C-n>")
      inc row
      check row < e.buffers.len
    e.settlePreview()
    check e.state.picker.preview.reads.len == 0
    require e.pickerPreviewView.buffer != nil
    check e.pickerPreviewView.buffer.id == aId
    check e.pickerPreviewView.title == "Preview"
    e.typeKeys("<C-c>")
    check e.closeBuffer(aId).isOk
    e.typeKeys(":picker resume<Enter>")
    e.settlePreview()
    check e.pickerPreviewView.buffer.isNil
    check e.pickerPreviewView.message == "Buffer no longer available"

  test "A cut file's title says so":
    let e = newPreviewEditor()
    let (a, b) = (dir / "big.txt", dir / "small.txt")
    writeFile(a, numbered("big", 150_000))
    writeFile(b, "small\n")
    check getFileSize(a) > PreviewMaxBytes
    e.openFilePicker([a, b])
    e.settlePreview()
    check e.pickerPreviewView.title == "Preview (first 1 MiB)"
    e.typeKeys("<C-n>")
    e.settlePreview()
    check e.pickerPreviewView.title == "Preview"

  test "Under the list, the preview has its title on the rule above it":
    let e = newPreviewEditor()
    let a = dir / "a.txt"
    writeFile(a, numbered("line", 3))
    e.openFilePicker([a])
    e.settlePreview()
    let screen = e.frame(80, 24)
    let layout = e.state.pickerScreenLayout(80, 24)
    check not layout.previewBeside
    let p = layout.preview
    check p.height > 0
    let rule = screen.row(p.y - 1, layout.frame.x, layout.frame.x + layout.frame.width)
    check rule.startsWith("├")
    check rule.endsWith("┤")
    check " Preview " in rule
    check screen.row(p.y, p.x, p.x + p.width).strip == "line 0"
    check screen.row(p.y + 2, p.x, p.x + p.width).strip == "line 2"

  test "A file read before is shown again without a read, the oldest dropped":
    let e = newPreviewEditor()
    var paths: seq[string]
    for i in 0 .. PreviewReadsKept:
      paths.add dir / ("f" & $i & ".txt")
      writeFile(paths[^1], "f" & $i & "\n")
    e.openFilePicker(paths)
    e.settlePreview()
    let first = e.pickerPreviewView.buffer
    e.typeKeys("<C-n>")
    e.settlePreview()
    e.typeKeys("<C-p>")
    e.settlePreview()
    check e.state.picker.preview.reads.len == 2
    check e.pickerPreviewView.buffer == first
    check e.state.picker.preview.reads[0].path == paths[0]
    for _ in 1 .. PreviewReadsKept:
      e.typeKeys("<C-n>")
      e.settlePreview()
    let reads = e.state.picker.preview.reads
    check reads.len == PreviewReadsKept
    check reads[0].path == paths[^1]
    check reads.findRead(paths[0]) < 0
    check reads.findRead(paths[1]) >= 0

  test "Why an item shows nothing is drawn in the preview":
    let e = newPreviewEditor()
    let a = dir / "bin"
    writeFile(a, "a\0b")
    e.openFilePicker([a])
    e.settlePreview()
    let screen = e.frame()
    let p = e.state.pickerScreenLayout(120, 40).preview
    check screen.row(p.y, p.x, p.x + p.width).strip == "A binary file"

  test "A scroll typed before the file is read is kept once it is":
    let e = newPreviewEditor()
    let a = dir / "a.txt"
    writeFile(a, numbered("a", 100))
    e.openFilePicker([a])
    discard e.frame()
    check e.state.picker.preview.reads.len == 0
    check e.handleKeyCombo(ShiftDown)
    check e.state.picker.preview.reads.len == 0
    e.settlePreview()
    check e.pickerPreviewView.buffer.getLine(0) == "a 0"
    check e.halfPreview > 0
    check e.pickerPreviewView.topLine == e.halfPreview

  test "The list of pickers has no preview":
    let e = newPreviewEditor()
    e.typeKeys(":picker<Enter>")
    check e.state.isPickerOverlay
    check not e.state.picker.previews
    check e.state.pickerScreenLayout(120, 40).preview.height == 0

suite "picker preview: layout":
  test "Beside the list on a wide screen":
    let l = pickerLayout(120, 40, 2, preview = true)
    check l.previewBeside
    check l.preview.width > 0
    check l.list.x + l.list.width < l.preview.x
    check l.preview.x + l.preview.width == l.frame.x + l.frame.width - 1
    check l.preview.height == l.frame.height - 2

  test "Under the list on a narrow screen":
    let l = pickerLayout(80, 24, 2, preview = true)
    check not l.previewBeside
    check l.preview.height > 0
    check l.list.y + l.list.height < l.preview.y
    check l.preview.y + l.preview.height == l.frame.y + l.frame.height - 1
    check l.list.width == l.frame.width - 2

  test "Nowhere on a small screen":
    let l = pickerLayout(40, 12, 2, preview = true)
    check l.preview.height == 0
    check l.list.height == l.frame.height - 4

  test "Nowhere without something to preview":
    let l = pickerLayout(120, 40, 2)
    check l.preview.height == 0
    check l.list.width == l.frame.width - 2
