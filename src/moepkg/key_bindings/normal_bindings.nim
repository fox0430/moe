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

## Default Normal-mode key bindings.
##
## Stored as a single `seq[tuple[key, cmd: string]]` and replayed against the
## registry by `bindNormalMode`. The string form of `bindKey` is used for every
## entry, which works for arrow keys / Home / End / PageUp / PageDown /
## Backspace / Enter / Tab / Escape / Space and Ctrl-modified keys (`C-s` etc.)
## via `parseKeyCombo` — so no `KeyCombo(...)` literals appear here.

import ../modes
import ./registry

const NormalBindings: seq[tuple[key, cmd: string]] = @[
  # Basic motion
  ("h", "move-left"),
  ("j", "move-down"),
  ("k", "move-up"),
  ("l", "move-right"),
  ("C-j", "move-down"), # CTRL-J / <NL> = down (Vim built-in)
  ("C-b", "page-up"),
  ("C-u", "half-page-up"),
  ("C-d", "half-page-down"),
  ("C-f", "page-down"),
  ("C-e", "scroll-line-down"),
  ("C-y", "scroll-line-up"),
  # Edit history
  ("u", "undo"),
  ("C-r", "redo"),
  ("C-a", "increment-number"),
  ("C-x", "decrement-number"),
  # Jump / changelist
  ("C-o", "jump-back"),
  ("C-i", "jump-forward"),
  ("Tab", "jump-forward"), # Tab = Ctrl-I in terminal
  ("g ;", "changelist-prev"),
  ("g ,", "changelist-next"),
  # Bookmarks
  ("m m", "bookmark-toggle"),
  ("m n", "bookmark-next"),
  ("m p", "bookmark-prev"),
  ("m c", "bookmark-clear"),
  # Search navigation
  ("n", "search-next"),
  ("N", "search-prev"),
  ("*", "search-word-forward"),
  ("#", "search-word-backward"),
  ("%", "match-bracket"),
  # Viewport motion
  ("H", "viewport-high"),
  ("M", "viewport-middle"),
  ("L", "viewport-low"),
  # Word motion
  ("w", "word-forward"),
  ("b", "word-backward"),
  ("e", "word-end"),
  ("g e", "word-end-backward"),
  # Paragraph motion
  ("}", "paragraph-forward"),
  ("{", "paragraph-backward"),
  # Line motion
  ("0", "line-home"),
  ("^", "line-first-non-blank"),
  ("_", "line-first-non-blank"),
  ("$", "line-end"),
  # Arrow keys and aliases
  ("Left", "move-left"),
  ("Right", "move-right"),
  ("Up", "move-up"),
  ("Down", "move-down"),
  ("Home", "line-home"),
  ("End", "line-end"),
  ("PageUp", "page-up"),
  ("PageDown", "page-down"),
  ("Backspace", "move-left"),
  ("Enter", "next-line-first-non-blank"),
  ("+", "next-line-first-non-blank"),
  ("-", "previous-line-first-non-blank"),
  # Paste
  ("p", "paste-after"),
  ("P", "paste-before"),
  # Misc
  ("J", "join-lines"),
  ("g a", "show-char-info"),
  # LSP
  ("g d", "lsp-goto-definition"),
  ("g r", "lsp-find-references"),
  ("g L", "lsp-codelens-execute"),
  ("g c", "lsp-goto-declaration"),
  ("g y", "lsp-goto-type-definition"),
  ("g i", "lsp-goto-implementation"),
  ("g h", "lsp-call-hierarchy"),
  ("g H", "lsp-call-hierarchy-outgoing"),
  ("K", "lsp-hover"),
  ("Space r", "lsp-rename"),
  ("Space o", "lsp-document-symbol"),
  ("C-s", "lsp-selection-range"),
  ("g l", "lsp-document-link"),
  ("g f", "open-uri"),
  # Save and quit
  ("Z Z", "save-and-quit"),
  ("Z Q", "quit-force"),
  # Window management
  ("C-w c", "close-window"),
  ("C-w k", "window-next"),
  ("C-w j", "window-prev"),
  ("C-w +", "window-increase-height"),
  ("C-w -", "window-decrease-height"),
  ("C-w >", "window-increase-width"),
  ("C-w <", "window-decrease-width"),
  ("C-w =", "window-equalize"),
  ("C-w x", "window-swap"),
  # Macro / register
  ("q", "macro-record"),
  ("@", "macro-play"),
  ("\"", "register-select"),
  # Indent / outdent / auto-indent
  (">", "operator-indent"),
  ("<", "operator-outdent"),
  ("= =", "autoindent-line"),
  # Scroll (z*)
  ("z t", "scroll-cursor-top"),
  ("z z", "scroll-cursor-center"),
  ("z .", "scroll-cursor-center"),
  ("z b", "scroll-cursor-bottom"),
  # Fold (z*); zf is bound in visual mode
  ("z o", "fold-open"),
  ("z c", "fold-close"),
  ("z a", "fold-toggle"),
  ("z d", "fold-delete"),
  ("z D", "fold-delete-all"),
  ("z R", "fold-open-all"),
  ("z M", "fold-close-all"),
  # QuickRun
  ("\\ r", "quickrun"),
  # Operators
  ("d", "operator-delete"),
  ("c", "operator-change"),
  ("y", "operator-yank"),
  ("g u", "operator-lowercase"),
  ("g U", "operator-uppercase"),
  # Character ops
  ("D", "delete-to-end"),
  ("C", "change-to-end"),
  ("x", "delete-char"),
  ("X", "delete-char-before"),
  ("s", "substitute-char"),
    # Note: "c u" sequence removed because it conflicts with operator+motion.
    # In Vim, "cu" is change operator + u motion, not substitute-char.
  ("S", "substitute-line"),
  ("~", "toggle-case"),
  (".", "repeat-last-change"),
  # Text objects (i / a are dispatched contextually as text object OR insert)
  ("i", "textobject-inner"),
  ("a", "textobject-around"),
  # Note: No bindKey for `"` in Normal mode — register-select takes precedence.
  # Text objects are handled by pendingTextObject raw dispatch.
  ("'", "textobject-quote-single"),
  ("(", "textobject-paren"),
  (")", "textobject-paren"),
  ("[", "textobject-bracket"),
  ("]", "textobject-bracket"),
  # Note: { and } are bound to paragraph motion above; they are used as text
  # objects only in operator-pending mode (e.g., di{).
  # Git change navigation
  ("] c", "navigate-git-next"),
  ("[ c", "navigate-git-prev"),
  # Git merge conflict navigation
  ("] x", "navigate-conflict-next"),
  ("[ x", "navigate-conflict-prev"),
  # find / till
  ("f", "find-char"),
  ("F", "find-char-backward"),
  ("t", "till-char"),
  ("T", "till-char-backward"),
  (";", "repeat-find"),
  (",", "repeat-find-reverse"),
  ("r", "replace-char"),
  # Buffer switching
  ("g t", "buffer-next-tab"),
  ("g T", "buffer-prev-tab"),
  ("g n", "search-next-select"),
  ("g N", "search-prev-select"),
  # g-sequences
  ("g g", "goto-first-line"),
  ("g _", "line-last-non-blank"),
  ("G", "goto-last-line"),
  # Normal → Insert transitions (i / a above are textobject-* which the
  # handler resolves to insert when no operator is pending)
  ("I", "insert-first-non-blank"),
  ("A", "append-end"),
  ("o", "open-line-below"),
  ("O", "open-line-above"),
  # Overlay switches
  (":", "switch-to-command"),
  ("/", "switch-to-search"),
  ("?", "switch-to-search-backward"),
  # Visual / Replace mode switches
  ("v", "switch-to-visual"),
  ("V", "switch-to-visual-line"),
  ("C-v", "switch-to-visual-block"),
  ("R", "switch-to-replace"),
]

proc bindNormalMode*(registry: KeyBindingRegistry) =
  ## Apply every default Normal-mode binding. Must run after the registry has
  ## been populated by `registerAllCommands` because `bindKey(string-form)`
  ## silently skips entries whose target command name is not yet registered.
  for (key, cmd) in NormalBindings:
    registry.bindKey(EditorMode.Normal, key, cmd)
