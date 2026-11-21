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

## A picker's preview of the selected item: a buffer of the editor as it is,
## or the start of a file no buffer holds, read as `:e` reads it once the
## selection rests on it, kept for a few files and highlighted a frame's
## budget at a time.

import std/[monotimes, options, os, strutils, times]

import pkg/results

import ../types/editor_types
import ../[types, buffer, encoding, buffer_load_config, unicode_utils]
import session

const
  PreviewMaxBytes* = 1024 * 1024 ## The start of a larger file is read
  PreviewSettle* = initDuration(milliseconds = 50)
    ## How long the selection rests on a file before it is read
  PreviewReadsKept = 8
  PreviewHighlightBudget = 2000 ## Lines highlighted a frame
  Title = "Preview"

type PickerPreviewView* = object
  title*: string
  message*: string ## Why the item shows nothing
  buffer*: TextBuffer ## Nil with nothing to show
  topLine*: int

proc cutAtLineEnd*(head: string, encoding: CharacterEncoding): string =
  ## `head`, the start of a longer file in `encoding`, up to and with its last
  ## line ending, or to its last whole character with none, so it decodes as
  ## the file does: a cut in a character fails the decode, and the text shows
  ## raw.
  case encoding
  of CharacterEncoding.utf8:
    let lineEnd = head.rfind('\n')
    if lineEnd >= 0:
      return head[0 .. lineEnd]
    let tail = head.utf8TruncatedTailStart
    if tail >= 0:
      head[0 ..< tail]
    else:
      head
  of CharacterEncoding.utf16, CharacterEncoding.utf16Le, CharacterEncoding.utf16Be,
      CharacterEncoding.utf32, CharacterEncoding.utf32Le, CharacterEncoding.utf32Be:
    let
      unit =
        if encoding in {
          CharacterEncoding.utf16, CharacterEncoding.utf16Le, CharacterEncoding.utf16Be
        }: 2 else: 4
      littleEndian =
        case encoding
        of CharacterEncoding.utf16Le, CharacterEncoding.utf32Le:
          true
        of CharacterEncoding.utf16, CharacterEncoding.utf32:
          head.startsWith("\xFF\xFE")
        else:
          false
      zeros = repeat('\0', unit - 1)
      newline =
        if littleEndian:
          "\n" & zeros
        else:
          zeros & "\n"
    var whole = head.len - head.len mod unit
    var i = whole - unit
    while i >= 0:
      if head.continuesWith(newline, i):
        return head[0 ..< i + unit]
      i -= unit
    if unit == 2 and whole >= 2:
      # A high surrogate wants the low one the cut left out.
      let (a, b) = (ord(head[whole - 2]), ord(head[whole - 1]))
      let last =
        if littleEndian:
          a or b shl 8
        else:
          a shl 8 or b
      if last in 0xD800 .. 0xDBFF:
        whole -= 2
    head[0 ..< whole]
  else:
    head

proc readHead(path: string, limit: int, size: int64): string =
  ## The start of `path` as it is now, `limit` bytes at most. `size`, what it
  ## held when looked at, only sizes the first read: it may have grown or
  ## shrunk since.
  var f: File
  if not f.open(path, fmRead):
    raise newException(IOError, "cannot open the file")
  defer:
    f.close()
  result = newString(int(clamp(size + 1, 1'i64, limit.int64)))
  var got = 0
  while true:
    got += f.readBuffer(result[got].addr, result.len - got)
    if got < result.len or result.len == limit:
      break
    result.setLen(min(limit, result.len * 2))
  result.setLen(got)

proc readPreview*(path: string, config: EditorConfig): PreviewRead =
  ## The file at `path` read for the preview: decoded as `:e` decodes it, its
  ## start when it is larger than `PreviewMaxBytes`, and into a buffer the
  ## editor does not hold. Anything but a regular file is not read: opening a
  ## pipe waits for a writer.
  result.path = path
  result.stamp = captureFileStamp(path)
  let size = regularFileSize(path)
  if size < 0:
    result.message =
      if dirExists(path):
        "A directory"
      else:
        try:
          discard getFileInfo(path)
          "Not a regular file"
        except OSError:
          "No such file"
    return
  var head: string
  try:
    # A byte past the limit tells a cut from a file of the limit's size.
    head = readHead(path, PreviewMaxBytes + 1, size)
  except IOError, OSError:
    result.message = "Cannot read: " & getCurrentExceptionMsg().forDisplay
    return
  # Decided from the whole start read, before the cut leaves less of it.
  var encoding = CharacterEncoding.unknown
  if head.len > PreviewMaxBytes:
    result.cut = true
    head.setLen(PreviewMaxBytes)
    encoding = detectCharacterEncoding(head)
    head = head.cutAtLineEnd(encoding)
  var decoded = decodeForBuffer(head, encoding)
  if decoded.hasBinaryContent:
    result.message = "A binary file"
    return
  let b = newTextBuffer(detached = true)
  b.loadWithConfig(config):
    let loaded =
      b.loadFileWithDecoded(path, head, decoded, head.len, some(result.stamp))
    if loaded.isErr:
      result.message = "Cannot read: " & loaded.error.forDisplay
      return
  result.buffer = b

proc findRead(reads: seq[PreviewRead], path: string): int =
  for i, read in reads:
    if read.path == path:
      return i
  -1

proc subjectOf(e: Editor, target: PickerTarget): PreviewSubject =
  ## A file a buffer holds shows the buffer, edits and all.
  case target.kind
  of ptkBuffer:
    PreviewSubject(kind: pvBuffer, buffer: target.buffer)
  of ptkFile:
    let held = bufferHoldingPath(e.buffers, target.path)
    if held.isSome:
      PreviewSubject(kind: pvBuffer, buffer: held.get.id)
    else:
      PreviewSubject(kind: pvFile, path: target.path)
  of ptkExCommand:
    PreviewSubject(kind: pvNone)

proc selectedItemIndex(s: PickerSession): Option[int] =
  let row = s.selectedRow
  if row < 0:
    none(int)
  else:
    some(s.rowItem(row))

proc previewSubject*(e: Editor, now: MonoTime): PreviewSubject =
  ## The selected item's subject, worked out again when the selection moved
  ## to another item. A file read before is read again if it changed since.
  let s = e.state.picker
  let item = s.selectedItemIndex
  if item != s.preview.item:
    s.preview.item = item
    s.preview.since = now
    s.preview.subject =
      if item.isSome:
        e.subjectOf(s.items[item.get].target)
      else:
        PreviewSubject(kind: pvNone)
    if s.preview.subject.kind == pvFile:
      let path = s.preview.subject.path
      let i = s.preview.reads.findRead(path)
      if i >= 0 and s.preview.reads[i].stamp != captureFileStamp(path):
        s.preview.reads.delete(i)
  s.preview.subject

proc advancePickerPreview*(e: Editor, now: MonoTime, onScreen: bool) =
  ## Read the selected item's file once the selection rested on it for
  ## `PreviewSettle`, so items gone over at a key's repeat are not read, and
  ## highlight it a frame's budget at a time: the editor's sweep goes over its
  ## own buffers only. Nothing is read while the screen has no room for the
  ## preview (`onScreen` false).
  let s = e.state.picker
  if s.isNil or not s.previews or not onScreen:
    return
  let subject = e.previewSubject(now)
  if subject.kind != pvFile:
    return
  template reads(): untyped =
    s.preview.reads

  let i = reads.findRead(subject.path)
  if i < 0:
    if now - s.preview.since < PreviewSettle:
      return
    reads.insert(readPreview(subject.path, e.config), 0)
    if reads.len > PreviewReadsKept:
      reads.setLen(PreviewReadsKept)
  elif i > 0:
    let read = reads[i]
    reads.delete(i)
    reads.insert(read, 0)
  if reads[0].buffer != nil:
    discard reads[0].buffer.advanceUndrawnHighlight(PreviewHighlightBudget)

proc shownBuffer(
    e: Editor, subject: PreviewSubject
): tuple[buffer: TextBuffer, message: string, cut: bool] =
  ## What `subject` shows now, from the buffers and the files read only.
  case subject.kind
  of pvNone:
    discard
  of pvBuffer:
    let b = e.bufferById(subject.buffer)
    if b.isNone:
      result.message = "Buffer no longer available"
    else:
      result.buffer = b.get
  of pvFile:
    let i = e.state.picker.preview.reads.findRead(subject.path)
    if i >= 0:
      let read = e.state.picker.preview.reads[i]
      result.buffer = read.buffer
      result.message = read.message
      result.cut = read.cut

proc scrolled(s: PickerSession, item: Option[int], lineCount: int): int =
  ## The selected item's scroll, short of the last line.
  let scroll = if s.preview.scrollItem == item: s.preview.scroll else: 0
  clamp(scroll, 0, max(0, lineCount - 1))

proc scrollPickerPreview*(e: Editor, lines: int, now: MonoTime) =
  ## Scroll the selected item's preview `lines` down, up when negative, as
  ## Vim's CTRL-E and CTRL-Y: no further than the last line at the top. A
  ## file still to be read keeps the scroll it is given.
  let s = e.state.picker
  if s.isNil or not s.previews:
    return
  let shown = e.shownBuffer(e.previewSubject(now))
  let item = s.preview.item
  if item.isNone:
    return
  var scroll =
    if shown.buffer != nil:
      s.scrolled(item, shown.buffer.len)
    elif s.preview.scrollItem == item:
      s.preview.scroll
    else:
      0
  scroll = max(0, scroll + lines)
  if shown.buffer != nil:
    scroll = min(scroll, max(0, shown.buffer.len - 1))
  s.preview.scroll = scroll
  s.preview.scrollItem = item

proc pickerPreviewView*(e: Editor): PickerPreviewView =
  ## What the preview shows of the selected item, as the frame worked it out.
  let s = e.state.picker
  if s.isNil or not s.previews:
    return
  let item = s.selectedItemIndex
  if item != s.preview.item:
    return
  if s.preview.subject.kind == pvNone:
    return
  let shown = e.shownBuffer(s.preview.subject)
  result.title = Title
  if shown.cut:
    result.title.add " (first " & $(PreviewMaxBytes div (1024 * 1024)) & " MiB)"
  result.message = shown.message
  result.buffer = shown.buffer
  if shown.buffer != nil:
    result.topLine = s.scrolled(item, shown.buffer.len)
