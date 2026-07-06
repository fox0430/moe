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

## Consistency test: every real key binding must be documented in the help
## viewer / howtouse.md, or explicitly allowlisted.
##
## The keybinding tables in `key_bindings/{normal,visual,insert}_bindings.nim`
## are the source of truth for what the editor actually does. The help text is
## hand-authored as `HelpGroup` constants in `help_generator.nim` (rendered to
## both the TUI help viewer and the markdown doc via `help_markdown.nim`).
## These two drift easily — a new binding silently never reaches the docs.
##
## This test compares them at the granularity of `tokenizeKey` token sequences
## (reusing the already-tested tokenizer in `help_markdown.nim`), so the
## spelling differences vanish: binding `"g d"` and help `"gd"` both tokenize
## to `@["g", "d"]`; binding `"C-w +"` and help `"Ctrl-w +"` both become
## `@["Ctrl", "w", "+"]`.
##
## Direction is forward only (every binding -> documented). The reverse is
## deliberately not checked: operator x text-object combinations (`di"`,
## `ciw`, `yt any`) are listed in help but exist only as runtime-composed
## parts in the registry, so they have no single binding to match.
##
## The allowlist is the human checkpoint: putting a binding there is the
## explicit act of declaring it an intentional alias / part that is not
## documented on its own.
##
## Scope: only registry/const-driven modes are testable here — Normal, Visual,
## VisualBlock, VisualLine, Insert, Replace. The viewer modes (Backup, Diff,
## References, CallHierarchy, Filer, Terminal) dispatch through ad-hoc `case`
## statements (`list_viewer.nim` `handleListNavKey` plus per-handler blocks in
## `command_handlers/*_handler.nim`) with no enumerable key table, so their
## help coverage can only be reviewed by hand and is out of scope for this test.

import std/[strutils, unittest, options, sets]

import ../src/moepkg/[help_generator, help_markdown]
import ../src/moepkg/key_bindings/registry
import ../src/moepkg/key_bindings/normal_bindings {.all.}
import ../src/moepkg/key_bindings/visual_bindings {.all.}
import ../src/moepkg/key_bindings/insert_bindings {.all.}

proc keyComboTokens(kc: KeyCombo): seq[string] =
  ## Map one `KeyCombo` to the same token vocabulary `tokenizeKey` produces,
  ## so a parsed binding can be compared against a tokenized help syntax.
  ## A modifier becomes its own leading token (`Ctrl-j` -> `@["Ctrl", "j"]`),
  ## mirroring the hyphen-split in `tokenizeKey`.
  if kmCtrl in kc.modifiers:
    result.add "Ctrl"
  elif kmAlt in kc.modifiers:
    result.add "Alt"
  elif kmShift in kc.modifiers:
    result.add "Shift"
  if kc.isSpecial:
    result.add(
      case kc.special
      of skEnter:
        "Enter"
      of skTab, skBackTab:
        "Tab"
      of skBackspace:
        "Backspace"
      of skDelete:
        "Delete"
      of skEscape:
        "Esc"
      of skUp:
        "Up"
      of skDown:
        "Down"
      of skLeft:
        "Left"
      of skRight:
        "Right"
      of skPageUp:
        "Page Up"
      of skPageDown:
        "Page Down"
      of skHome:
        "Home"
      of skEnd:
        "End"
      of skFunction:
        "F" & $kc.fnNum
      of skNone:
        ""
    )
  elif kc.char == " ":
    result.add "Space"
  else:
    result.add kc.char

proc bindingTokens(key: string): seq[string] =
  ## Tokenize a binding key string the way `bindKey` consumes it: split on
  ## spaces into per-key parts, parse each, and concatenate the tokens.
  ## Returns an empty seq if any part fails to parse (a dead binding).
  for part in key.split(' '):
    if part.len == 0:
      continue
    let kc = parseKeyCombo(part)
    if kc.isNone:
      return @[]
    result.add keyComboTokens(kc.get)

proc helpTokenSeqs(groups: varargs[HelpGroup]): seq[seq[string]] =
  ## Collect the token sequence of every help entry, splitting ` or `
  ## alternations (mirroring `renderKbdKeysCell`) so each alternative is a
  ## separate documented form.
  for g in groups:
    for e in g.entries:
      for seg in e.syntax.split(" or "):
        result.add tokenizeKey(seg)

proc findUndocumented(
    bindings: seq[tuple[key, cmd: string]],
    helpTokens: seq[seq[string]],
    allowKeys: HashSet[string] = initHashSet[string](),
    allowCmds: HashSet[string] = initHashSet[string](),
    allowCmdPrefixes: seq[string] = @[],
): seq[string] =
  for (key, cmd) in bindings:
    let toks = bindingTokens(key)
    if toks.len == 0:
      result.add key & " (" & cmd & ") [unparseable binding]"
      continue
    if toks in helpTokens:
      continue
    if key in allowKeys or cmd in allowCmds:
      continue
    var allowed = false
    for p in allowCmdPrefixes:
      if cmd.startsWith(p):
        allowed = true
        break
    if allowed:
      continue
    result.add key & " (" & cmd & ")"

proc report(mode: string, missing: seq[string]) =
  if missing.len > 0:
    echo "Undocumented " & mode & "-mode bindings (add to a HelpGroup in " &
      "help_generator.nim, or allowlist in this test):"
    for m in missing:
      echo "  " & m

suite "help / keybinding consistency":
  test "Normal mode bindings are documented or allowlisted":
    # Normal-mode keys are split across the "Changing modes" and "Normal mode"
    # help sections, so both groups count as documentation.
    let help = helpTokenSeqs(NormalModeCommands, ChangingModesCommands)
    let allowKeys = toHashSet(
      [
        # Motion aliases of documented keys (arrows/Home/End/etc.).
        "Left",
        "Right",
        "Up",
        "Down",
        "Home",
        "End",
        "Backspace",
        "Enter",
        "+",
        "-",
        "_",
        # Tab == Ctrl-i (jump-forward), which is documented as "Ctrl-i".
        "Tab",
        # Text-object trigger chars: documented only via composed forms
        # (di", ci(, ...), never on their own.
        "'",
        "(",
        ")",
        "[",
        "]",
      ]
    )
    let allowCmds = toHashSet(
      [
        # Operators: documented via composed forms (dd, di", yiw, ...).
        "operator-delete",
        "operator-change",
        "operator-yank",
        # Register / macro prefixes: documented in their own sections / with
        # an "any" placeholder, not as a bare key in the Normal table.
        "register-select",
        "macro-play",
      ]
    )
    let missing = findUndocumented(NormalBindings, help, allowKeys, allowCmds)
    report("Normal", missing)
    check missing.len == 0

  test "Visual mode bindings are documented or allowlisted":
    let help = helpTokenSeqs(VisualModeCommands)
    let allowKeys = toHashSet(
      [
        # Text-object triggers (Visual-only); composed at runtime.
        "i", "a",
      ]
    )
    let allowCmds = toHashSet(
      [
        # Cursor motions shared with Normal mode — not re-listed in the
        # Visual help section.
        "visual-swap-selection",
        "visual-paste",
        # Exit alias (C-c). Esc is documented; C-c is the bare alias.
        "switch-to-normal",
        # VisualBlock-only block append.
        "visual-block-append",
      ]
    )
    let allVisual =
      @SharedVisualBindings & @VisualOnlyBindings & @VisualBlockOnlyBindings
    let missing =
      findUndocumented(allVisual, help, allowKeys, allowCmds, @["visual-move"])
    report("Visual", missing)
    check missing.len == 0

  test "Insert/Replace mode bindings are documented or allowlisted":
    # InsertReplaceBindings is registry-driven (Esc / C-c only). The richer
    # Insert keys (Ctrl-e, Ctrl-y, ...) are handled inside insert_handler.nim,
    # not the registry, so they are documentation-only and out of scope here.
    let help = helpTokenSeqs(InsertModeCommands, ReplaceModeCommands)
    let allowCmds = toHashSet(["switch-to-normal"]) # C-c alias; Esc documented
    let missing = findUndocumented(InsertReplaceBindings, help, allowCmds = allowCmds)
    report("Insert/Replace", missing)
    check missing.len == 0
