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

import pkg/results

import types, buffer, key_bindings, registers, unicode_utils, char_class

type
  PromptKey* = enum
    pkOther ## A key the prompt reads as it is
    pkEnter ## Enter, which runs the line
    pkRun
      ## An Esc a mapping or a register put in, which runs the line as it
      ## stands (`:h c_<Esc>`)
    pkLeave ## A typed Esc, or Ctrl-C however it came
    pkArgument ## The key a Ctrl-R or a Ctrl-V waits for

  LineEdit* = enum
    leNone ## Not a key that edits the line
    leStill ## A key that edits the line, with nothing to do
    leBeep ## Up or Down with nowhere to go, where Vim beeps
    leMoved ## The cursor moved, or went to the start or the end it was already at
    leTyped ## A character went in at the cursor
    leErased ## Text before or under the cursor went
    lePasted ## Text went in that was not typed as such
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

proc takeKey*(
    line: var PromptLine, key: KeyCombo, typed: bool, interrupted = false
): PromptKey =
  ## What `key` does to the prompt. A key that does not browse the history
  ## ends what Up and Down look for, whatever it then does. A Ctrl-R waits
  ## for any key but an interrupt; a Ctrl-V for that too.
  if line.wait != pwNone:
    if line.wait == pwLiteral or not (key.isCtrlC and interrupted):
      return pkArgument
    line.wait = pwNone
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
  line.wait = pwNone
  line.insert(firstLine)
  true

proc erase(line: var PromptLine, key: KeyCombo): LineEdit =
  ## Backspace or Ctrl-H, or Delete, which takes the character under the
  ## cursor or, at the end, the one before it, as Vim's cmdline_erase_chars.
  if line.text.len == 0:
    return leEmptyErase
  let runes = line.text.toCharRunes
  var at = line.cursor
  if key.isSpecial and key.special == skDelete and at < runes.len:
    at = runes.nextCharColumn(at)
  if at == 0:
    return leStill
  line.cursor = runes.baseColumn(at - 1)
  for column in countdown(at - 1, line.cursor):
    line.text = line.text.deleteCharAt(column)
  leErased

proc eraseToStart(line: var PromptLine): LineEdit =
  ## Ctrl-U: all before the cursor. An empty line stays open, unlike with
  ## Backspace.
  if line.cursor == 0:
    return leStill
  line.text = line.text[charToBytePos(line.text, line.cursor) ..^ 1]
  line.cursor = 0
  leErased

proc wordStart(line: PromptLine): int =
  ## Where Ctrl-W stops, as Vim's cmdline_erase_chars: back over white space,
  ## then to the start of the run of one character class.
  let runes = line.text.toCharRunes
  result = runes.baseColumn(line.cursor - 1)
  while result > 0 and runes[result].isVimSpace:
    result = runes.baseColumn(result - 1)
  let class = mbClass(runes[result])
  while result > 0 and mbClass(runes[result]) == class:
    result = runes.baseColumn(result - 1)
  if mbClass(runes[result]) != class:
    result = runes.nextCharColumn(result)

proc eraseWord(line: var PromptLine): LineEdit =
  ## Ctrl-W: the word before the cursor. An empty line stays open.
  if line.cursor == 0:
    return leStill
  let start = line.wordStart
  line.text =
    line.text[0 ..< charToBytePos(line.text, start)] &
    line.text[charToBytePos(line.text, line.cursor) ..^ 1]
  line.cursor = start
  leErased

proc moveTo(line: var PromptLine, cursor: int, toAnEnd = false): LineEdit =
  ## A move to the start or the end (Home, End, Ctrl-B, Ctrl-E) is one even
  ## with the cursor already there.
  if cursor == line.cursor and not toAnEnd:
    return leStill
  line.cursor = cursor
  leMoved

proc charLeft(line: PromptLine): int =
  ## The character before the cursor, with the composing characters on it.
  if line.cursor > 0:
    line.text.toCharRunes.baseColumn(line.cursor - 1)
  else:
    0

proc charRight(line: PromptLine): int =
  ## The character after the one under the cursor, past its composing
  ## characters.
  let runes = line.text.toCharRunes
  if line.cursor < runes.len:
    runes.nextCharColumn(line.cursor)
  else:
    line.cursor

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

proc literalText(key: KeyCombo): string =
  ## What Ctrl-V puts in for `key`: its character, the control character of
  ## Ctrl with a letter, else its name as Vim writes it. Backspace is the
  ## character a terminal sends for it.
  if key.isSpecial:
    if key.modifiers == {}:
      case key.special
      of skEnter:
        return "\r"
      of skEscape:
        return "\e"
      of skTab:
        return "\t"
      of skBackspace:
        return "\x7f"
      else:
        discard
    return key.keyComboToString.multiReplace(
      ("Delete", "Del"), ("Backspace", "BS"), ("Enter", "CR"), ("Escape", "Esc")
    )
  if key.modifiers == {}:
    return key.char
  if key.modifiers - {kmShift} == {kmCtrl} and key.char.len == 1:
    let c = key.char[0].toUpperAscii
    if c in {'@', ' '}:
      return "\n" # Vim keeps a NUL as a line feed; Ctrl-@ comes as Ctrl-Space
    if c == '?':
      return "\x7f"
    if c in '@' .. '_':
      return $chr(ord(c) - 0x40)
  key.keyComboToString

proc codeText(value: int): string =
  ## The character with code `value`. Vim keeps a NUL as a line feed; one no
  ## character has comes out as the replacement character.
  if value == 0:
    "\n"
  elif value > 0x10FFFF or value in 0xD800 .. 0xDFFF:
    "\uFFFD"
  else:
    Rune(value).toUTF8

proc readCode(
    line: var PromptLine, key: KeyCombo
): Option[tuple[text: string, unread: bool]] =
  ## Take `key` as the next of what Ctrl-V reads, as Vim's get_literal: a key
  ## as it is, or a code of up to three decimal digits, `o` and three octal
  ## ones, `x` and two hex ones, `u` and four or `U` and eight. The letters
  ## count wherever they come, as in Vim. The text once it is all read, with
  ## `unread` when `key` ended a code without being part of it.
  template code(): untyped =
    line.literal

  var ended = key.isSpecial or key.modifiers - {kmShift} != {} or key.char.len != 1
  if not ended:
    let c = key.char[0]
    case c
    of 'x', 'X':
      code.hex = true
    of 'o', 'O':
      code.octal = true
    of 'u':
      code.unicodeDigits = 4
    of 'U':
      code.unicodeDigits = 8
    else:
      let
        base =
          if code.hex or code.unicodeDigits > 0:
            16
          elif code.octal:
            8
          else:
            10
        digit =
          case c
          of '0' .. '9':
            ord(c) - ord('0')
          of 'a' .. 'f':
            ord(c) - ord('a') + 10
          of 'A' .. 'F':
            ord(c) - ord('A') + 10
          else:
            base
      if digit >= base:
        ended = true
      else:
        code.value = code.value * base + digit
        inc code.digits
    if code.value > 255 and code.unicodeDigits == 0:
      code.value = 255
  let full =
    if code.hex:
      code.digits >= 2
    elif code.unicodeDigits > 0:
      code.digits >= code.unicodeDigits
    else:
      code.digits >= 3
  if not ended and not full:
    return none((string, bool))
  line.wait = pwNone
  if code.digits == 0:
    some((key.literalText, false))
  else:
    some((code.value.codeText, ended))

proc edit*(line: var PromptLine, key: KeyCombo, history: seq[string]): LineEdit =
  ## Edit the line with `key`, as Vim's getcmdline: move in it, put in a
  ## character, erase, or go through `history` (newest first). Ctrl-R and
  ## Ctrl-V begin here and `editPrompt` reads what they wait for.
  if key.isSpecial:
    let shifted = key.modifiers * {kmShift, kmCtrl} != {}
    case key.special
    of skLeft:
      line.moveTo(if shifted: line.wordLeft else: line.charLeft)
    of skRight:
      line.moveTo(if shifted: line.wordRight else: line.charRight)
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
  elif key.isCtrl('u'):
    line.eraseToStart
  elif key.isCtrl('w'):
    line.eraseWord
  elif key.isCtrl('r'):
    line.wait = pwRegister
    leStill
  elif key.isCtrl('v') or key.isCtrl('q'):
    line.wait = pwLiteral
    line.literal = LiteralCode()
    leStill
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

const
  CtrlV = Rune(0x16)
  CtrlVKey = KeyCombo(isSpecial: false, char: "v", modifiers: {kmCtrl})
  ActsWhenTyped = {
    '\x02', '\x05', '\x08', '\x0e', '\x10', '\x11', '\x12', '\x15', '\x16', '\x17',
    '\x1d', '\x1e',
  }
    ## The control characters a prompt takes as keys, the ones that do nothing
    ## there among them (Ctrl-], Ctrl-^). Any other goes in as it is.

proc isControl(r: Rune): bool =
  r.int < 0x20 or r.int == 0x7f

proc keyOf(r: Rune): KeyCombo =
  ## The key that types `r`.
  case r.int
  of 0x09:
    KeyCombo(isSpecial: true, special: skTab)
  of 0x0d:
    KeyCombo(isSpecial: true, special: skEnter)
  of 0x1b:
    KeyCombo(isSpecial: true, special: skEscape)
  of 0x7f:
    KeyCombo(isSpecial: true, special: skBackspace)
  of 0x00 .. 0x08, 0x0a .. 0x0c, 0x0e .. 0x1a, 0x1c .. 0x1f:
    KeyCombo(
      isSpecial: false, char: $chr(r.int + 0x40).toLowerAscii, modifiers: {kmCtrl}
    )
  else:
    KeyCombo(isSpecial: false, char: r.toUTF8)

proc asTyped(lines: openArray[string]): tuple[plain: string, keys: seq[KeyCombo]] =
  ## `lines` as Vim's cmdline_paste_reg types them, each with a CR between
  ## them put in by cmdline_paste_str on its own, so a Ctrl-V that ends one
  ## covers nothing: what is plain up to the first character a prompt takes as
  ## a key, then the rest as keys, each character that would end the line or
  ## that a Ctrl-V covers after a Ctrl-V.
  for n, text in lines:
    if n > 0:
      if result.keys.len == 0:
        result.plain.add '\r'
      else:
        result.keys.add [CtrlVKey, Rune('\r').keyOf]
    var at = 0
    if result.keys.len == 0:
      while at < text.len and text[at] notin ActsWhenTyped:
        inc at
      result.plain.add text[0 ..< at]
    let runes = text[at ..^ 1].toRunes
    var i = 0
    while i < runes.len:
      let viaCtrlV = runes[i] == CtrlV
      if viaCtrlV and i + 1 < runes.len:
        inc i
      let r = runes[i]
      inc i
      if viaCtrlV or (r.isControl and char(r.int) notin ActsWhenTyped):
        result.keys.add CtrlVKey
      result.keys.add r.keyOf

proc runOnLine(line: var PromptLine, keys: seq[KeyCombo]): int =
  ## Run the first of `keys` that only edit the line, so what follows an edit
  ## runs once for them all, as Vim's char_avail has it. Returns how many ran:
  ## one that reads a register or the history stops it, and one the line does
  ## not take or that would leave the prompt.
  while result < keys.len:
    let key = keys[result]
    if line.wait == pwLiteral:
      let read = line.readCode(key)
      if read.isSome:
        line.insert(read.get.text)
        if read.get.unread:
          continue
    elif key.isCtrl('r') or key.isCtrl('p') or key.isCtrl('n') or
        line.edit(key, @[]) in {leNone, leEmptyErase}:
      return
    inc result

proc withoutTypedPart(line: PromptLine, word: string, ignoreCase: bool): string =
  ## `word` past the keyword before the cursor when it starts with that, as
  ## 'incsearch' has Ctrl-R Ctrl-W go on from what was typed of the word.
  let runes = line.text.toCharRunes
  var start = line.cursor
  while start > 0 and mbClass(runes[start - 1]) >= 2:
    dec start
  let typed =
    line.text[charToBytePos(line.text, start) ..< charToBytePos(line.text, line.cursor)]
  if (
    if ignoreCase:
      word.toLowerAscii.startsWith(typed.toLowerAscii)
    else:
      word.startsWith(typed)
  ):
    word[typed.len ..^ 1]
  else:
    word

proc textOfLine(state: EditorState, b: TextBuffer, index: int): string =
  ## The line `index` of `b`, as it is before a `:s` preview changed it.
  template preview(): untyped =
    state.ui.substitutePreview

  if preview.isActive and index < preview.originalLines.len:
    preview.originalLines[index]
  elif index < b.len:
    b.getLine(index)
  else:
    ""

proc registerText(
    state: EditorState, b: TextBuffer, key: KeyCombo
): Result[seq[string], string] =
  ## The lines Ctrl-R puts in for `key`, a CR to go between them: none for a
  ## key that names no register or a register with no text. The last of
  ## linewise text is empty, so it ends in a CR as well. The read-only
  ## registers fail as Vim's get_spec_reg does.
  template line(): untyped =
    state.input.line

  if key.isCtrl('w') or key.isCtrl('a'):
    let
      at = line.wordAt.get(state.cursor)
      text = state.textOfLine(b, at.line)
      found = text.identInLine(at.column, ident = key.isCtrl('w'))
    if found.isNone:
      return err("E348: No string under cursor")
    return ok(
      @[
        text[
          charToBytePos(text, found.get.startCol) ..<
            charToBytePos(text, found.get.endCol)
        ]
      ]
    )
  if key.isCtrl('l'):
    return ok(@[state.textOfLine(b, line.wordAt.get(state.cursor).line)])
  if key.isSpecial or key.modifiers != {} or key.char.len != 1:
    return ok(newSeq[string]())
  let name = key.char[0]
  case name
  of '%':
    if b.filePath.isNone:
      return err("E32: No file name")
    ok(@[b.filePath.get])
  of '/':
    if state.input.search.last.pattern.len == 0:
      return err("E35: No previous regular expression")
    ok(@[state.input.search.last.pattern])
  of ':':
    if state.input.commandState.history.len == 0:
      return err("E30: No previous command line")
    ok(@[state.input.commandState.history[0]])
  else:
    if not name.isValidRegisterName:
      return ok(newSeq[string]())
    ok(
      (?state.registers.textToPut(name, state.config.clipboard)).getContent.split('\n')
    )

proc readRegister(state: EditorState, b: TextBuffer, key: KeyCombo): LineEdit =
  ## Take `key` as what Ctrl-R reads, as Vim's cmdline_insert_reg: a register
  ## or an object under the cursor, after Ctrl-R or Ctrl-O for its text
  ## literally. The text goes in as if typed otherwise, but for what would end
  ## the line, and the system's selections always literally.
  template line(): untyped =
    state.input.line

  if line.wait == pwRegister and (key.isCtrl('r') or key.isCtrl('o')):
    line.wait = pwRegisterLiterally
    return leStill
  let literally =
    line.wait == pwRegisterLiterally or (
      not key.isSpecial and key.modifiers == {} and key.char.len == 1 and
      key.char[0].isClipboardRegisterName
    )
  line.wait = pwNone
  let found = state.registerText(b, key)
  if found.isErr:
    state.statusMessage = found.error
    return leBeep
  var lines = found.get
  if key.isCtrl('w') and state.input.search.incsearch:
    lines[0] = line.withoutTypedPart(lines[0], state.input.search.ignorecase)
  let (plain, keys) =
    if literally:
      (lines.join("\r"), newSeq[KeyCombo]())
    else:
      lines.asTyped
  line.insert(plain)
  let ran = line.runOnLine(keys)
  for k in keys[ran ..^ 1]:
    state.stuffedKeys.add (k, false)
  if plain.len == 0 and ran == 0: leStill else: lePasted

proc editPrompt*(
    state: EditorState, b: TextBuffer, key: KeyCombo, history: seq[string]
): LineEdit =
  ## Run `key` on the open prompt: `edit`, or what a Ctrl-R or a Ctrl-V waits
  ## for. `b` is the buffer the keys that read text take it from.
  template line(): untyped =
    state.input.line

  case line.wait
  of pwNone:
    line.edit(key, history)
  of pwRegister, pwRegisterLiterally:
    state.readRegister(b, key)
  of pwLiteral:
    let read = line.readCode(key)
    if read.isNone:
      return leStill
    line.insert(read.get.text)
    if read.get.unread:
      state.stuffedKeys.add (key, state.keyTyped)
    lePasted
