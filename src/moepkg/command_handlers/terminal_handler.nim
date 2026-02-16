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

## Terminal mode command handler
##
## Handles input in Terminal mode. Has two sub-modes:
## - Terminal-Input: forwards keystrokes to PTY
## - Terminal-Normal: Vim-like scrollback navigation

import std/options

import ../[terminal_mode, key_bindings]

type
  TerminalResultKind* = enum
    trHandled # Key was forwarded to PTY or processed
    trSwitchToNormal # Switch to Terminal-Normal sub-mode
    trReturnToInput # Return to Terminal-Input sub-mode
    trEnterCommand # Enter command mode (:)
    trQuit # Close terminal
    trUnhandled # Key not handled (delegate to normal mode in tsmNormal)
    trError # Error occurred

  TerminalResult* = object
    case kind*: TerminalResultKind
    of trError:
      errorMessage*: string
    else:
      discard

  TerminalHandler* = ref object ## Handler for Terminal mode specific commands
    discard

proc newTerminalHandler*(): TerminalHandler =
  TerminalHandler()

proc keyComboToBytes*(keyCombo: KeyCombo): string =
  ## Convert a KeyCombo to raw terminal bytes for PTY forwarding.
  if keyCombo.isSpecial:
    case keyCombo.special
    of skEnter:
      return "\r"
    of skEscape:
      return "\x1b"
    of skBackspace:
      return "\x7f"
    of skTab:
      return "\t"
    of skBackTab:
      return "\x1b[Z"
    of skUp:
      return "\x1b[A"
    of skDown:
      return "\x1b[B"
    of skRight:
      return "\x1b[C"
    of skLeft:
      return "\x1b[D"
    of skHome:
      return "\x1b[H"
    of skEnd:
      return "\x1b[F"
    of skDelete:
      return "\x1b[3~"
    of skPageUp:
      return "\x1b[5~"
    of skPageDown:
      return "\x1b[6~"
    of skFunction:
      # Function keys F1-F12
      case keyCombo.fnNum
      of 1:
        return "\x1bOP"
      of 2:
        return "\x1bOQ"
      of 3:
        return "\x1bOR"
      of 4:
        return "\x1bOS"
      of 5:
        return "\x1b[15~"
      of 6:
        return "\x1b[17~"
      of 7:
        return "\x1b[18~"
      of 8:
        return "\x1b[19~"
      of 9:
        return "\x1b[20~"
      of 10:
        return "\x1b[21~"
      of 11:
        return "\x1b[23~"
      of 12:
        return "\x1b[24~"
      else:
        return ""
    of skNone:
      return ""
  else:
    if kmCtrl in keyCombo.modifiers:
      # Ctrl+letter -> ASCII control character
      if keyCombo.char.len == 1:
        let ch = keyCombo.char[0]
        if ch >= 'a' and ch <= 'z':
          return $chr(ch.ord - 'a'.ord + 1)
        elif ch >= 'A' and ch <= 'Z':
          return $chr(ch.ord - 'A'.ord + 1)
      return ""
    elif kmAlt in keyCombo.modifiers:
      # Alt+key -> ESC + key
      return "\x1b" & keyCombo.char
    else:
      return keyCombo.char

proc handleTerminalModeKey*(
    handler: TerminalHandler, termState: TerminalState, keyCombo: KeyCombo
): TerminalResult =
  ## Handle a key press in Terminal mode.

  case termState.subMode
  of tsmInput:
    # Terminal-Input sub-mode: forward almost everything to PTY

    # Check for Ctrl-\ (escape sequence to enter Normal sub-mode)
    if not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
        keyCombo.char in ["\\", "\x1c"]:
      termState.waitingForCtrlN = true
      return TerminalResult(kind: trHandled)

    # If waiting for Ctrl-N after Ctrl-\
    if termState.waitingForCtrlN:
      termState.waitingForCtrlN = false
      if not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
          keyCombo.char in ["n", "N"]:
        return TerminalResult(kind: trSwitchToNormal)
      # Not Ctrl-N, forward the original Ctrl-\ and this key
      termState.feedInput("\x1c")
      let bytes = keyComboToBytes(keyCombo)
      if bytes.len > 0:
        termState.feedInput(bytes)
      return TerminalResult(kind: trHandled)

    # Forward key to PTY
    let bytes = keyComboToBytes(keyCombo)
    if bytes.len > 0:
      termState.feedInput(bytes)
    return TerminalResult(kind: trHandled)
  of tsmNormal:
    # Terminal-Normal sub-mode: Vim-like scrollback navigation

    # 'i' or 'a' returns to Terminal-Input sub-mode
    if not keyCombo.isSpecial and keyCombo.modifiers == {}:
      case keyCombo.char
      of "i", "a":
        return TerminalResult(kind: trReturnToInput)
      of ":":
        return TerminalResult(kind: trEnterCommand)
      of "q":
        # Close terminal if process has exited
        if termState.exitCode.isSome:
          return TerminalResult(kind: trQuit)
        # Otherwise ignore (process still running)
        return TerminalResult(kind: trHandled)
      else:
        discard

    # Delegate unhandled keys to normal mode navigation (j/k/gg/G/search etc.)
    return TerminalResult(kind: trUnhandled)
