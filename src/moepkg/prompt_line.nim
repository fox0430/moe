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

## The line typed at a prompt: the command line, the search prompt and the
## LSP rename's. They end, edit and browse their history alike, as Vim's
## getcmdline does for each.

import std/[options, strutils, unicode]

import types, key_bindings, unicode_utils

type
  PromptKey* = enum
    pkOther ## A key the prompt reads as it is
    pkEnter ## Enter, which runs the line
    pkRun
      ## An Esc a mapping or a register put in, which runs the line as it
      ## stands (`:h c_<Esc>`)
    pkLeave ## A typed Esc, or Ctrl-C however it came

  LineEdit* = enum
    leNone ## Not a key that edits the line
    leStill ## A key that edits the line, with nothing to do
    leBeep ## Up or Down with nowhere to go, where Vim beeps
    leMoved ## The cursor moved, or went to the start or the end it was already at
    leTyped ## A character went in at the cursor
    leErased ## The character before or under the cursor went
    leRecalled ## A history entry, or what Up looked for, took the line
    leEmptyErase
      ## An erase on an empty line, which leaves the `:` and `/` prompts but
      ## not one with words of its own, as Vim's input() with a prompt

proc promptKey(key: KeyCombo, typed: bool): PromptKey =
  if key.isSpecial:
    case key.special
    of skEnter:
      pkEnter
    of skEscape:
      if typed: pkLeave else: pkRun
    else:
      pkOther
  elif key.char == "\n" or key.char == "\r" or key.isCtrl('j') or key.isCtrl('m'):
    pkEnter
  elif key.isCtrlC:
    pkLeave
  else:
    pkOther

proc keepsLookfor(key: KeyCombo): bool =
  ## Up and Down, plain Left and Right, and Ctrl-P and Ctrl-N, which Vim's
  ## getcmdline lets keep what Up and Down look for.
  if key.isSpecial:
    case key.special
    of skUp, skDown, skPageUp, skPageDown:
      true
    of skLeft, skRight:
      key.modifiers * {kmShift, kmCtrl} == {}
    else:
      false
  else:
    key.isCtrl('p') or key.isCtrl('n')

proc takeKey*(line: var PromptLine, key: KeyCombo, typed: bool): PromptKey =
  ## What `key` does to the prompt. A key that does not browse the history
  ## ends what Up and Down look for, whatever it then does.
  if not key.keepsLookfor:
    line.lookfor = none(string)
  promptKey(key, typed)

proc insert(line: var PromptLine, s: string) =
  ## Put `s` in at the cursor and the cursor after it.
  let at = charToBytePos(line.text, line.cursor)
  line.text = line.text[0 ..< at] & s & line.text[at ..^ 1]
  # From the end byte, so bytes that join across the seam keep the cursor.
  line.cursor = byteToCharPos(line.text, at + s.len)

proc insertPasted*(line: var PromptLine, text: string): bool =
  ## A paste's first line at the cursor, as the line is one line. Returns
  ## whether anything went in.
  let
    newline = text.find('\n')
    firstLine = (if newline >= 0: text[0 ..< newline] else: text).replace("\r", "")
  if firstLine.len == 0:
    return false
  line.lookfor = none(string)
  line.insert(firstLine)
  true

proc erase(line: var PromptLine, key: KeyCombo): LineEdit =
  ## Backspace or Ctrl-H, or Delete, which takes the character under the
  ## cursor or, at the end, the one before it, as Vim's cmdline_erase_chars.
  if line.text.len == 0:
    return leEmptyErase
  var at = line.cursor
  if key.isSpecial and key.special == skDelete and at < line.text.charLen:
    at.inc
  if at == 0:
    return leStill
  line.text = line.text.deleteCharAt(at - 1)
  line.cursor = at - 1
  leErased

proc moveTo(line: var PromptLine, cursor: int, toAnEnd = false): LineEdit =
  ## A move to the start or the end (Home, End, Ctrl-B, Ctrl-E) is one even
  ## with the cursor already there.
  if cursor == line.cursor and not toAnEnd:
    return leStill
  line.cursor = cursor
  leMoved

proc wordLeft(line: PromptLine): int =
  ## Vim's S-Left: one character left, then on to just after a space.
  let runes = line.text.toCharRunes
  result = line.cursor
  if result == 0:
    return
  dec result
  while result > 0 and runes[result - 1] != Rune(' '):
    dec result

proc wordRight(line: PromptLine): int =
  ## Vim's S-Right: one character right, then on to a space or the end.
  let runes = line.text.toCharRunes
  result = line.cursor
  if result >= runes.len:
    return
  inc result
  while result < runes.len and runes[result] != Rune(' '):
    inc result

proc browse(
    line: var PromptLine, history: seq[string], older, filtered: bool
): LineEdit =
  ## Up and Down, as Vim's cmdline_browse_history: `filtered` ones go to the
  ## entries that start with the text that was before the cursor when they
  ## began, and Down past the newest puts that text back. `history` has the
  ## newest first.
  if line.lookfor.isNone:
    line.lookfor = some(line.text[0 ..< charToBytePos(line.text, line.cursor)])
  let lookfor = line.lookfor.get
  if line.entry.isSome and line.entry.get > history.high:
    # The entry has gone from the history since it was recalled.
    line.entry = none(int)
  let start = line.entry
  var at = start
  while true:
    if older:
      let next =
        if at.isNone:
          0
        else:
          at.get + 1
      if next > history.high:
        at = start
        break
      at = some(next)
    elif at.isNone:
      break
    elif at.get == 0:
      at = none(int)
      break
    else:
      at = some(at.get - 1)
    if not filtered or history[at.get].startsWith(lookfor):
      break
  if at == start:
    return leBeep
  line.entry = at
  line.text =
    if at.isSome:
      history[at.get]
    else:
      lookfor
  line.cursor = line.text.charLen
  leRecalled

proc edit*(line: var PromptLine, key: KeyCombo, history: seq[string]): LineEdit =
  ## Edit the line with `key`, as Vim's getcmdline: move in it, put in a
  ## character, erase one, or go through `history` (newest first).
  if key.isSpecial:
    let shifted = key.modifiers * {kmShift, kmCtrl} != {}
    case key.special
    of skLeft:
      line.moveTo(
        if shifted:
          line.wordLeft
        else:
          max(line.cursor - 1, 0)
      )
    of skRight:
      line.moveTo(
        if shifted:
          line.wordRight
        else:
          min(line.cursor + 1, line.text.charLen)
      )
    of skHome:
      line.moveTo(0, toAnEnd = true)
    of skEnd:
      line.moveTo(line.text.charLen, toAnEnd = true)
    of skUp, skDown:
      line.browse(history, key.special == skUp, filtered = kmShift notin key.modifiers)
    of skPageUp, skPageDown:
      line.browse(history, key.special == skPageUp, filtered = false)
    of skBackspace, skDelete:
      line.erase(key)
    else:
      leNone
  elif key.isCtrlH:
    line.erase(key)
  elif key.isCtrl('b'):
    line.moveTo(0, toAnEnd = true)
  elif key.isCtrl('e'):
    line.moveTo(line.text.charLen, toAnEnd = true)
  elif key.isCtrl('p') or key.isCtrl('n'):
    line.browse(history, key.isCtrl('p'), filtered = false)
  elif key.modifiers == {}:
    line.insert(key.char)
    leTyped
  else:
    leNone
