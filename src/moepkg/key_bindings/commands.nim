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

## Default command registration tables for the key-binding system.
##
## Each table lists the (name, description, ...) of one `Command` kind.
## `registerAllCommands` iterates over the tables and builds the corresponding
## `Command` variants. This keeps `setupDefaultBindings` in `key_bindings.nim`
## free of the 183 hand-written `registerCommand` calls it used to contain.

import std/tables

import ../[types, modes, command_config]
import ./registry

const MotionCommands: seq[tuple[name, desc: string, motion: Motion]] = @[
  ("move-left", "Move cursor left", Motion.Left),
  ("move-right", "Move cursor right", Motion.Right),
  ("move-up", "Move cursor up", Motion.Up),
  ("move-down", "Move cursor down", Motion.Down),
  ("page-up", "Scroll page up", Motion.PageUp),
  ("page-down", "Scroll page down", Motion.PageDown),
  ("half-page-up", "Scroll half page up", Motion.HalfPageUp),
  ("half-page-down", "Scroll half page down", Motion.HalfPageDown),
  ("line-home", "Move to beginning of line", Motion.Home),
  (
    "line-first-non-blank", "Move to first non-whitespace character",
    Motion.FirstNonBlank,
  ),
  ("line-last-non-blank", "Move to last non-whitespace character", Motion.LastNonBlank),
  ("line-end", "Move to end of line", Motion.End),
  ("goto-first-line", "Go to first line", Motion.FirstLine),
  ("goto-last-line", "Go to last line", Motion.LastLine),
  ("viewport-high", "Move to top of viewport", Motion.ViewportHigh),
  ("viewport-middle", "Move to middle of viewport", Motion.ViewportMiddle),
  ("viewport-low", "Move to bottom of viewport", Motion.ViewportLow),
  (
    "next-line-first-non-blank", "Move to next line's first non-whitespace character",
    Motion.NextLineFirstNonBlank,
  ),
  (
    "previous-line-first-non-blank",
    "Move to previous line's first non-whitespace character",
    Motion.PreviousLineFirstNonBlank,
  ),
  ("word-forward", "Move to start of next word", Motion.WordForward),
  ("word-backward", "Move to start of previous word", Motion.WordBackward),
  ("word-end", "Move to end of next word", Motion.WordEnd),
  ("word-end-backward", "Move to end of previous word", Motion.WordEndBackward),
  ("paragraph-forward", "Move to next paragraph", Motion.ParagraphForward),
  ("paragraph-backward", "Move to previous paragraph", Motion.ParagraphBackward),
  ("match-bracket", "Jump to matching bracket (%)", Motion.MatchBracket),
  ("repeat-find", "Repeat last f/F/t/T", Motion.RepeatFind),
  ("repeat-find-reverse", "Repeat last f/F/t/T reversed", Motion.RepeatFindReverse),
]

const ActionCommands: seq[tuple[name, desc, commandId: string]] = @[
  ("undo", "Undo last change", "edit.undo"),
  ("redo", "Redo last undone change", "edit.redo"),
  ("increment-number", "Increment number at or after cursor", "edit.increment"),
  ("decrement-number", "Decrement number at or after cursor", "edit.decrement"),
  ("jump-back", "Jump to previous position in jump list", "jump.back"),
  ("jump-forward", "Jump to next position in jump list", "jump.forward"),
  ("changelist-prev", "Jump to previous change position", "changelist.prev"),
  ("changelist-next", "Jump to next change position", "changelist.next"),
  ("bookmark-toggle", "Toggle bookmark on current line", "bookmark.toggle"),
  ("bookmark-next", "Jump to next bookmark", "bookmark.next"),
  ("bookmark-prev", "Jump to previous bookmark", "bookmark.prev"),
  ("bookmark-clear", "Clear all bookmarks in current buffer", "bookmark.clear"),
  ("search-next", "Find next search result", "search.next"),
  ("search-prev", "Find previous search result", "search.prev"),
  (
    "search-word-forward", "Search for word under cursor forward (*)",
    "search.word.forward",
  ),
  (
    "search-word-backward", "Search for word under cursor backward (#)",
    "search.word.backward",
  ),
  ("search-next-select", "Select next search match (gn)", "search.next.select"),
  ("search-prev-select", "Select previous search match (gN)", "search.prev.select"),
  ("clipboard-copy", "Copy selected text to system clipboard", "edit.copy"),
  ("clipboard-paste", "Paste text from system clipboard", "edit.paste"),
  ("clipboard-cut", "Cut selected text to system clipboard", "edit.cut"),
  ("save", "Save file", "file.save"),
  ("save-and-quit", "Save file and quit", "file.save.and.quit"),
  ("quit-force", "Quit without saving", "file.quit.force"),
  ("close-window", "Close current window", "window.close"),
  ("window-next", "Switch to next window", "window.next"),
  ("window-prev", "Switch to previous window", "window.prev"),
  ("window-increase-height", "Increase window height", "window.increase-height"),
  ("window-decrease-height", "Decrease window height", "window.decrease-height"),
  ("window-increase-width", "Increase window width", "window.increase-width"),
  ("window-decrease-width", "Decrease window width", "window.decrease-width"),
  ("window-equalize", "Equalize all window sizes", "window.equalize"),
  ("window-swap", "Swap window with next window", "window.swap"),
  ("macro-record", "Start/stop macro recording", "macro.record"),
  ("file-open", "Open file (enter filer)", "file.open"),
  ("file-new", "Create new empty buffer", "file.new"),
  ("file-close", "Close current buffer", "file.close"),
  ("filer-open", "Open file explorer", "filer.open"),
  ("repeat-last-change", "Repeat last change", "edit.repeat"),
  ("buffer-next-tab", "Switch to next buffer tab", "buffer.next.tab"),
  ("buffer-prev-tab", "Switch to previous buffer tab", "buffer.prev.tab"),
  ("open-line-below", "Open new line below and enter insert mode", "insert.line.below"),
  ("open-line-above", "Open new line above and enter insert mode", "insert.line.above"),
  ("append", "Append after cursor", "insert.append"),
  ("append-end", "Append at end of line", "insert.append.end"),
  (
    "insert-first-non-blank", "Insert at first non-blank character",
    "insert.first.non.blank",
  ),
  (
    "insert-backspace", "Delete character before cursor (insert mode)",
    "insert.backspace",
  ),
  ("insert-delete", "Delete character at cursor (insert mode)", "insert.delete"),
  ("insert-newline", "Insert newline (insert mode)", "insert.newline"),
  ("visual-move-left", "Move left in visual mode", "visual.move.left"),
  ("visual-move-right", "Move right in visual mode", "visual.move.right"),
  ("visual-move-up", "Move up in visual mode", "visual.move.up"),
  ("visual-move-down", "Move down in visual mode", "visual.move.down"),
  ("visual-delete", "Delete visual selection", "visual.delete"),
  ("visual-yank", "Yank visual selection", "visual.yank"),
  ("visual-indent", "Indent visual selection", "visual.indent"),
  ("visual-dedent", "Dedent visual selection", "visual.dedent"),
  ("visual-lowercase", "Convert visual selection to lowercase", "visual.lowercase"),
  ("visual-uppercase", "Convert visual selection to uppercase", "visual.uppercase"),
  ("visual-toggle-case", "Toggle case of visual selection", "visual.togglecase"),
  ("visual-joinlines", "Join lines in visual selection", "visual.joinlines"),
  ("visual-move-home", "Move to beginning of line in visual mode", "visual.move.home"),
  ("visual-move-end", "Move to end of line in visual mode", "visual.move.end"),
  (
    "visual-move-firstnonblank", "Move to first non-blank character in visual mode",
    "visual.move.firstnonblank",
  ),
  (
    "visual-move-firstline", "Move to first line in visual mode",
    "visual.move.firstline",
  ),
  ("visual-move-lastline", "Move to last line in visual mode", "visual.move.lastline"),
  ("visual-move-word", "Move to next word in visual mode", "visual.move.word"),
  (
    "visual-move-word-back", "Move to previous word in visual mode",
    "visual.move.word.back",
  ),
  ("visual-move-word-end", "Move to end of word in visual mode", "visual.move.word.end"),
  (
    "visual-move-word-end-backward", "Move to end of previous word in visual mode",
    "visual.move.word.end.backward",
  ),
  (
    "visual-move-paragraph-forward", "Move to next paragraph in visual mode",
    "visual.move.paragraph.forward",
  ),
  (
    "visual-move-paragraph-backward", "Move to previous paragraph in visual mode",
    "visual.move.paragraph.backward",
  ),
  (
    "visual-swap-selection", "Swap cursor to other end of selection",
    "visual.swap.selection",
  ),
  ("visual-to-insert", "Enter insert mode from visual selection", "visual.to.insert"),
  ("visual-change", "Delete selection and enter insert mode", "visual.change"),
  ("visual-block-append", "Append after visual block selection", "visual.block.append"),
  ("visual-paste", "Delete selection and paste register content", "visual.paste"),
]

const CustomCommands: seq[tuple[name, desc, commandId: string]] = @[
  ("delete-word", "Delete word", "delete.word"),
  ("delete-line", "Delete line", "delete.line"),
  ("yank-line", "Yank (copy) line", "yank.line"),
  ("paste-after", "Paste after cursor", "paste.after"),
  ("paste-before", "Paste before cursor", "paste.before"),
  ("join-lines", "Join current line with next line", "join.lines"),
  (
    "show-char-info", "Show ASCII/Unicode value of character under cursor",
    "show.char.info",
  ),
  ("lsp-goto-definition", "Go to definition (LSP)", "lsp.goto.definition"),
  ("lsp-find-references", "Find all references (LSP)", "lsp.find.references"),
  (
    "lsp-codelens-execute", "Execute CodeLens on current line (LSP)",
    "lsp.codelens.execute",
  ),
  ("lsp-goto-declaration", "Go to declaration (LSP)", "lsp.goto.declaration"),
  (
    "lsp-goto-type-definition", "Go to type definition (LSP)",
    "lsp.goto.type.definition",
  ),
  ("lsp-goto-implementation", "Go to implementation (LSP)", "lsp.goto.implementation"),
  ("lsp-call-hierarchy", "Show call hierarchy (LSP)", "lsp.callhierarchy.incoming"),
  (
    "lsp-call-hierarchy-outgoing", "Show outgoing call hierarchy (LSP)",
    "lsp.callhierarchy.outgoing",
  ),
  ("lsp-hover", "Show hover information (LSP)", "lsp.hover"),
  ("lsp-rename", "Rename symbol (LSP)", "lsp.rename"),
  ("lsp-document-symbol", "Show document symbols (LSP)", "lsp.document.symbol"),
  ("lsp-selection-range", "Expand selection range (LSP)", "lsp.selection.range"),
  ("lsp-document-link", "Follow document link at cursor (LSP)", "lsp.document.link"),
  ("open-uri", "Open URI/file under cursor", "editor.open.uri"),
  ("operator-indent", "Indent operator", "operator.indent"),
  ("operator-outdent", "Outdent operator", "operator.outdent"),
  ("autoindent-line", "Auto indent current line", "autoindent.line"),
  ("scroll-cursor-top", "Scroll cursor to top of screen", "scroll.cursor.top"),
  ("scroll-cursor-center", "Scroll cursor to center of screen", "scroll.cursor.center"),
  ("scroll-cursor-bottom", "Scroll cursor to bottom of screen", "scroll.cursor.bottom"),
  ("scroll-line-down", "Scroll viewport one line down", "scroll.line.down"),
  ("scroll-line-up", "Scroll viewport one line up", "scroll.line.up"),
  ("fold-open", "Open fold at cursor", "fold.open"),
  ("fold-close", "Close fold at cursor", "fold.close"),
  ("fold-toggle", "Toggle fold at cursor", "fold.toggle"),
  ("fold-open-all", "Open all folds", "fold.open.all"),
  ("fold-close-all", "Close all folds", "fold.close.all"),
  ("fold-create", "Create fold from selection", "fold.create"),
  ("fold-delete", "Delete fold at cursor", "fold.delete"),
  ("fold-delete-all", "Delete all folds", "fold.delete.all"),
  ("quickrun", "Run current buffer", "quickrun"),
  ("operator-delete", "Delete operator", "operator.delete"),
  ("operator-change", "Change operator", "operator.change"),
  ("operator-yank", "Yank operator", "operator.yank"),
  ("operator-lowercase", "Lowercase operator", "operator.lowercase"),
  ("operator-uppercase", "Uppercase operator", "operator.uppercase"),
  ("delete-to-end", "Delete to end of line", "operator.delete.to.end"),
  ("change-to-end", "Change to end of line", "operator.change.to.end"),
  ("delete-char", "Delete character at cursor", "delete.char"),
  ("delete-char-before", "Delete character before cursor", "delete.char.before"),
  ("substitute-char", "Substitute character at cursor", "substitute.char"),
  ("substitute-line", "Substitute line", "substitute.line"),
  ("toggle-case", "Toggle case of character at cursor", "toggle.case"),
  ("textobject-inner", "Inner text object", "textobject.inner"),
  ("textobject-around", "Around text object", "textobject.around"),
  ("textobject-word", "Word text object", "textobject.word"),
  ("textobject-quote-double", "Double quote text object", "textobject.quote.double"),
  ("textobject-quote-single", "Single quote text object", "textobject.quote.single"),
  ("textobject-paren", "Parenthesis text object", "textobject.paren"),
  ("textobject-bracket", "Bracket text object", "textobject.bracket"),
  ("textobject-brace", "Brace text object", "textobject.brace"),
  ("navigate-git-next", "Next git change", "navigate.git.next"),
  ("navigate-git-prev", "Previous git change", "navigate.git.prev"),
  ("navigate-conflict-next", "Next git merge conflict", "navigate.conflict.next"),
  ("navigate-conflict-prev", "Previous git merge conflict", "navigate.conflict.prev"),
  ("change-word", "Change word", "change.word"),
]

const ModeSwitchCommands: seq[tuple[name, desc: string, target: EditorMode]] = @[
  ("switch-to-insert", "Switch to insert mode", EditorMode.Insert),
  ("switch-to-normal", "Switch to normal mode", EditorMode.Normal),
  ("switch-to-visual", "Switch to visual mode", EditorMode.Visual),
  ("switch-to-replace", "Switch to replace mode", EditorMode.Replace),
  ("switch-to-visual-block", "Switch to visual block mode", EditorMode.VisualBlock),
  ("switch-to-visual-line", "Switch to visual line mode", EditorMode.VisualLine),
]

const OverlaySwitchCommands: seq[tuple[name, desc: string, target: OverlayKind]] = @[
  ("switch-to-command", "Switch to command mode", okCommand),
  ("switch-to-search", "Switch to search mode (forward)", okSearch),
  ("switch-to-search-backward", "Switch to search mode (backward)", okSearch),
]

const OperatorPendingCommands: seq[tuple[name, desc, opType: string, reverse: bool]] = @[
  ("mark-set", "Set buffer-local named mark (a-z)", "mark-set", false),
  ("mark-line", "Jump to named mark line", "mark-line", false),
  ("mark-exact", "Jump to named mark position", "mark-exact", false),
  ("macro-play", "Play macro from register", "macro-play", false),
  ("register-select", "Select register for next command", "register-select", false),
  ("find-char", "Find character forward", "find", false),
  ("find-char-backward", "Find character backward", "find", true),
  ("till-char", "Till character forward", "till", false),
  ("till-char-backward", "Till character backward", "till", true),
  ("replace-char", "Replace character", "replace", false),
  (
    "visual-replace-char", "Replace visual selection with character", "visual-replace",
    false,
  ),
  (
    "visual-surround-char", "Surround visual selection with character",
    "visual-surround", false,
  ),
]

proc registerMotionCommands(reg: KeyBindingRegistry) =
  for (name, desc, motion) in MotionCommands:
    reg.registerCommand(
      Command(name: name, description: desc, kind: ctMotion, motion: motion)
    )

proc registerActionCommands(reg: KeyBindingRegistry) =
  for (name, desc, commandId) in ActionCommands:
    reg.registerCommand(
      Command(
        name: name, description: desc, kind: ctAction, commandId: commandId, args: @[]
      )
    )

proc registerCustomCommands(reg: KeyBindingRegistry) =
  for (name, desc, commandId) in CustomCommands:
    reg.registerCommand(
      Command(
        name: name, description: desc, kind: ctCustom, commandId: commandId, args: @[]
      )
    )

proc registerModeSwitchCommands(reg: KeyBindingRegistry) =
  for (name, desc, target) in ModeSwitchCommands:
    reg.registerCommand(
      Command(name: name, description: desc, kind: ctModeSwitch, targetMode: target)
    )

proc registerOverlaySwitchCommands(reg: KeyBindingRegistry) =
  for (name, desc, target) in OverlaySwitchCommands:
    reg.registerCommand(
      Command(
        name: name, description: desc, kind: ctOverlaySwitch, targetOverlay: target
      )
    )

proc registerOperatorPendingCommands(reg: KeyBindingRegistry) =
  for (name, desc, opType, reverse) in OperatorPendingCommands:
    reg.registerCommand(
      Command(
        name: name,
        description: desc,
        kind: ctOperatorPending,
        operatorType: opType,
        reverse: reverse,
        targetChar: "",
      )
    )

proc registerCommandModeAliases(reg: KeyBindingRegistry) =
  ## Register Command mode command aliases (`:bd`, `:q`, `:w`, `:bnext` ...)
  ## as keymap targets. Each is dispatched at runtime via `hrExecCommand` /
  ## `nmrExecCommand`, routing through the full command-line parser so safety
  ## checks (modified-buffer guard etc.) are inherited automatically. Names
  ## that already exist as registered Commands (e.g. "save") are skipped — the
  ## pre-existing handler already covers them with the right commandId.
  for alias in keyMappableCommandModeAliases:
    if reg.commandRegistry.hasKey(alias.name):
      continue
    reg.registerCommand(
      Command(
        name: alias.name,
        description: alias.description,
        kind: ctAction,
        commandId: ExecCmdlinePrefix & alias.name,
        args: @[],
      )
    )

proc registerAllCommands*(reg: KeyBindingRegistry) =
  ## Register every default `Command` consumed by `setupDefaultBindings`.
  ## Must run before any `bindKey(string-form)` calls, because that overload
  ## resolves command names against `reg.commandRegistry` at bind time and
  ## silently skips unknown names. The Command-mode alias loop must run last
  ## so its skip-if-exists check sees the pre-registered handlers.
  reg.registerMotionCommands()
  reg.registerActionCommands()
  reg.registerCustomCommands()
  reg.registerModeSwitchCommands()
  reg.registerOverlaySwitchCommands()
  reg.registerOperatorPendingCommands()
  reg.registerCommandModeAliases()
