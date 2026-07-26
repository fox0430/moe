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

## Default Visual / VisualBlock / VisualLine mode key bindings.
##
## The three modes share 45 bindings, so they live in `SharedVisualBindings`
## and are replayed against each mode in turn. The three differences observed
## in the original code are kept separate:
##
## * `i` / `a` (textobject-inner / textobject-around) — Visual only
## * `A` (visual-block-append) — VisualBlock only
## * (nothing) — VisualLine has no mode-specific bindings
##
## C-s (lsp-selection-range) is shared across all three; the original code
## bound it via a `KeyCombo(... modifiers: {kmCtrl})` literal in each mode,
## which `parseKeyCombo("C-s")` handles identically.

import ../modes
import ./registry

const SharedVisualBindings: seq[tuple[key, cmd: string]] = @[
  # Motion (hjkl + 0/$/^)
  ("h", "visual-move-left"),
  ("l", "visual-move-right"),
  ("j", "visual-move-down"),
  ("k", "visual-move-up"),
  ("C-j", "visual-move-down"), # CTRL-J / <NL> = down (Vim built-in)
  ("0", "visual-move-home"),
  ("$", "visual-move-end"),
  ("^", "visual-move-firstnonblank"),
  ("g g", "visual-move-firstline"),
  ("G", "visual-move-lastline"),
  # Word motion
  ("w", "visual-move-word"),
  ("b", "visual-move-word-back"),
  ("e", "visual-move-word-end"),
  ("g e", "visual-move-word-end-backward"),
  # Paragraph motion
  ("}", "visual-move-paragraph-forward"),
  ("{", "visual-move-paragraph-backward"),
  # Edit
  ("I", "visual-to-insert"),
  ("d", "visual-delete"),
  ("x", "visual-delete"),
  ("y", "visual-yank"),
  (">", "visual-indent"),
  ("<", "visual-dedent"),
  ("u", "visual-lowercase"),
  ("U", "visual-uppercase"),
  ("~", "visual-toggle-case"),
  ("r", "visual-replace-char"),
  ("S", "visual-surround-char"),
  ("J", "visual-joinlines"),
  ("c", "visual-change"),
  ("o", "visual-swap-selection"),
  ("p", "visual-paste"),
  ("P", "visual-paste"),
  # Fold
  ("z f", "fold-create"),
  # Adjust + LSP
  ("C-a", "increment-number"),
  ("C-x", "decrement-number"),
  ("C-s", "lsp-selection-range"),
  # Arrow keys and other navigation aliases
  ("Left", "visual-move-left"),
  ("Right", "visual-move-right"),
  ("Up", "visual-move-up"),
  ("Down", "visual-move-down"),
  ("Home", "visual-move-home"),
  ("End", "visual-move-end"),
  ("Backspace", "visual-move-left"),
  ("Enter", "visual-move-down"),
]

# Bindings that only apply to character-wise Visual mode. In VisualBlock and
# VisualLine, `i` / `a` have no dedicated meaning — text objects are dispatched
# via pendingTextObject raw flow instead.
const VisualOnlyBindings: seq[tuple[key, cmd: string]] =
  @[("i", "textobject-inner"), ("a", "textobject-around")]

# Bindings that only apply to VisualBlock mode.
const VisualBlockOnlyBindings: seq[tuple[key, cmd: string]] =
  @[("A", "visual-block-append")]

proc bindVisualModes*(registry: KeyBindingRegistry) =
  ## Apply default bindings for Visual / VisualBlock / VisualLine. Must run
  ## after `registerAllCommands` because `bindKey(string-form)` resolves
  ## command names lazily.
  for mode in [EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine]:
    for (key, cmd) in SharedVisualBindings:
      registry.bindKey(mode, key, cmd)
  for (key, cmd) in VisualOnlyBindings:
    registry.bindKey(EditorMode.Visual, key, cmd)
  for (key, cmd) in VisualBlockOnlyBindings:
    registry.bindKey(EditorMode.VisualBlock, key, cmd)
