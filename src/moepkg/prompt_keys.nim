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

## The keys that end the search prompt and the command line, and the ones
## that erase in them, taken alike by both, as Vim's getcmdline takes them.

import key_bindings, unicode_utils

type
  PromptKey* = enum
    pkOther ## A key the prompt reads as it is
    pkEnter ## Enter, which runs the line
    pkRun
      ## An Esc a mapping or a register put in, which runs the line as it
      ## stands (`:h c_<Esc>`)
    pkLeave ## A typed Esc, or Ctrl-C however it came
    pkErase ## Backspace, Ctrl-H or Delete

  EraseOutcome* = enum
    eoLeave ## The line was empty: the erase leaves the prompt
    eoUnchanged ## Backspace at the start of the line
    eoErased

proc promptKey*(key: KeyCombo, typed: bool): PromptKey =
  if key.isSpecial:
    case key.special
    of skEnter:
      pkEnter
    of skEscape:
      if typed: pkLeave else: pkRun
    of skBackspace, skDelete:
      pkErase
    else:
      pkOther
  elif key.char == "\n" or key.char == "\r" or key.isCtrl('j') or key.isCtrl('m'):
    pkEnter
  elif key.isCtrlC:
    pkLeave
  elif key.isCtrlH:
    pkErase
  else:
    pkOther

proc erase*(text: var string, cursor: var int, key: KeyCombo): EraseOutcome =
  ## Backspace or Ctrl-H, or Delete, which takes the character under the
  ## cursor or, at the end, the one before it. An erase on an empty line
  ## leaves the prompt, as Vim's cmdline_erase_chars.
  if text.len == 0:
    return eoLeave
  var at = cursor
  if key.isSpecial and key.special == skDelete and at < text.charLen:
    at.inc
  if at == 0:
    return eoUnchanged
  text = text.deleteCharAt(at - 1)
  cursor = at - 1
  eoErased
