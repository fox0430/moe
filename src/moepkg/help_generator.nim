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

## Compile-time generators for sections of the help viewer text.
##
## The simple key→description sections of `HelpSentences` (`# Exiting`,
## `# Changing modes`, `# Normal mode`, `# Register`, `# Visual mode`,
## `# Replace mode`, `# Insert mode`, `# Backup mode`, `# Diff mode`,
## `# References mode`, `# Call hierarchy viewer mode`, `# Filer mode`,
## and the two `# Terminal mode` sub-modes) are built from the
## corresponding `XxxCommands*` `HelpGroup` constants. The
## `# Command mode` subsection is built from `CommandLineCommandTable` +
## `CommandLineSpecialHelp` (in `command_line_commands`), and the
## `set` options block is built from the canonical `SetOptionTable` defined
## in `setting_options`. Each table is the structured source of truth; help
## text is assembled by the `renderXxxSection` `{.compileTime.}` procs and
## the resulting strings are embedded into `const HelpSentences`, so the
## runtime cost is zero.

import std/[options, strutils]

import setting_options, command_line_commands, help_description

descriptionFromStringConverter()
export setting_options, command_line_commands

type HelpGroup* = object
  ## A blank-line-separated subgroup of help lines with a shared
  ## left-column alignment.
  entries*: seq[HelpEntry]
  minWidth*: int
    ## Minimum left-column width. When 0 (default), the renderer uses
    ## the longest `syntax` in `entries`. Set this when the original
    ## hand-written text pads beyond that natural max (e.g. one extra
    ## trailing space for visual breathing room).

const ChangingModesCommands*: HelpGroup = HelpGroup(
  entries: @[
    HelpEntry(syntax: "v", description: "Visual mode"),
    HelpEntry(syntax: "Ctrl-v", description: "Visual block mode"),
    HelpEntry(syntax: "V", description: "Visual line mode"),
    HelpEntry(syntax: "R", description: "Replace mode"),
    HelpEntry(syntax: "i", description: "Insert mode"),
    HelpEntry(syntax: "o", description: "Insert a new line and start insert mode"),
    HelpEntry(syntax: "O", description: "Open a new line above and start insert mode"),
    HelpEntry(syntax: "a", description: "Append after the cursor and start insert mode"),
    HelpEntry(syntax: "I", description: "Same as ^i"),
    HelpEntry(syntax: "A", description: "Same as $a"),
  ]
)

const NormalModeCommands*: HelpGroup = HelpGroup(
  entries: @[
    HelpEntry(syntax: "h", description: "Go left"),
    HelpEntry(syntax: "j", description: "Go down"),
    HelpEntry(syntax: "Ctrl-j", description: "Go down"),
    HelpEntry(syntax: "k", description: "Go up"),
    HelpEntry(syntax: "l", description: "Go right"),
    HelpEntry(syntax: "w", description: "Go forwards to the start of a word"),
    HelpEntry(syntax: "e", description: "Go forwards to the end of a word"),
    HelpEntry(syntax: "ge", description: "Go backwards to the end of a word"),
    HelpEntry(syntax: "b", description: "Go backwards to the start of a word"),
    HelpEntry(syntax: "r", description: "Replace a character at the cursor"),
    HelpEntry(syntax: "Page Up", description: "Page Up"),
    HelpEntry(syntax: "Page Down", description: "Page Down"),
    HelpEntry(syntax: "gg", description: "Go to the first line"),
    HelpEntry(
      syntax: "g_", description: "Go to the last non-blank character of the line"
    ),
    HelpEntry(syntax: "g;", description: "Go to the previous change position"),
    HelpEntry(syntax: "g,", description: "Go to the next change position"),
    HelpEntry(syntax: "G", description: "Go to the last line"),
    HelpEntry(syntax: "0", description: "Go to the first character of the line"),
    HelpEntry(syntax: "$", description: "Go to the end of the line"),
    HelpEntry(
      syntax: "^", description: "Go to the first non-blank character of the line"
    ),
    HelpEntry(syntax: "{", description: "Go to the previous blank line"),
    HelpEntry(syntax: "}", description: "Go to the next blank line"),
    HelpEntry(syntax: "H", description: "Move to the top line of the screen"),
    HelpEntry(syntax: "M", description: "Move to the center line of the screen"),
    HelpEntry(syntax: "L", description: "Move to the bottom line of the screen"),
    HelpEntry(syntax: "Ctrl-b", description: "Page Up"),
    HelpEntry(syntax: "Ctrl-f", description: "Page Down"),
    HelpEntry(syntax: "Ctrl-u", description: "Half Page Up"),
    HelpEntry(syntax: "Ctrl-d", description: "Half Page Down"),
    HelpEntry(syntax: "%", description: "Move to matching pair of paren"),
    HelpEntry(syntax: "d$ or D", description: "Delete until the end of the line"),
    HelpEntry(syntax: "C", description: "Change until the end of the line"),
    HelpEntry(syntax: "yy or Y", description: "Copy a line"),
    HelpEntry(syntax: "y{", description: "Yank to the previous blank line"),
    HelpEntry(syntax: "y}", description: "Yank to the next blank line"),
    HelpEntry(syntax: "yl", description: "Yank a character"),
    HelpEntry(syntax: "yt any", description: "Yank characters to a any character"),
    HelpEntry(syntax: "p", description: "Paste the clipboard"),
    HelpEntry(syntax: "P", description: "Paste the clipboard before the cursor"),
    HelpEntry(syntax: "n", description: "Search forwards"),
    HelpEntry(syntax: "N", description: "Search backwards"),
    HelpEntry(
      syntax: "gn", description: "Go to next search match and select it visually"
    ),
    HelpEntry(
      syntax: "gN", description: "Go to previous search match and select it visually"
    ),
    HelpEntry(syntax: "dgn", description: "Delete next search match"),
    HelpEntry(syntax: "dgN", description: "Delete previous search match"),
    HelpEntry(syntax: "]c", description: "Jump to next git change hunk"),
    HelpEntry(syntax: "[c", description: "Jump to previous git change hunk"),
    HelpEntry(syntax: "]x", description: "Jump to next git merge conflict block"),
    HelpEntry(syntax: "[x", description: "Jump to previous git merge conflict block"),
    HelpEntry(syntax: ":", description: "Start command mode"),
    HelpEntry(syntax: "u", description: "Undo"),
    HelpEntry(syntax: "Ctrl-r", description: "Redo"),
    HelpEntry(syntax: "Ctrl-a", description: "Increase number under cursor"),
    HelpEntry(syntax: "Ctrl-x", description: "Decrease number under cursor"),
    HelpEntry(syntax: ">", description: "Indent"),
    HelpEntry(syntax: "<", description: "Unindent"),
    HelpEntry(syntax: "==", description: "Auto indent"),
    HelpEntry(syntax: "J", description: "Join lines"),
    HelpEntry(syntax: "dd", description: "Delete a line"),
    HelpEntry(syntax: "x", description: "Delete current character"),
    HelpEntry(syntax: "X or dh", description: "Delete the character before the cursor"),
    HelpEntry(syntax: "~", description: "Toggle case of character under cursor"),
    HelpEntry(syntax: "gu", description: "Lowercase (operator)"),
    HelpEntry(syntax: "gU", description: "Uppercase (operator)"),
    HelpEntry(
      syntax: "S or cc",
      description: "Delete the characters in the current line and start insert mode",
    ),
    HelpEntry(
      syntax: "s or cl",
      description: "Delete the current character and enter insert mode",
    ),
    HelpEntry(
      syntax: "ci\"",
      description: "Delete the inside of double quotes and enter insert mode",
    ),
    HelpEntry(
      syntax: "ci'",
      description: "Delete the inside of single quotes and enter insert mode",
    ),
    HelpEntry(
      syntax: "ciw", description: "Delete the current word and enter insert mode"
    ),
    HelpEntry(
      syntax: "ciW", description: "Delete the current WORD and enter insert mode"
    ),
    HelpEntry(
      syntax: "ci( or ci)",
      description: "Delete the inside of round brackets and enter insert mode",
    ),
    HelpEntry(
      syntax: "ci[ or ci]",
      description: "Delete the inside of square brackets and enter insert mode",
    ),
    HelpEntry(
      syntax: "ci{ or ci}",
      description: "Delete the inside of curly brackets and enter insert mode",
    ),
    HelpEntry(
      syntax: "ca\"", description: "Delete around double quotes and enter insert mode"
    ),
    HelpEntry(
      syntax: "ca'", description: "Delete around single quotes and enter insert mode"
    ),
    HelpEntry(
      syntax: "caw",
      description: "Delete a word (with surrounding whitespace) and enter insert mode",
    ),
    HelpEntry(
      syntax: "caW",
      description: "Delete a WORD (with surrounding whitespace) and enter insert mode",
    ),
    HelpEntry(
      syntax: "ca( or ca)",
      description: "Delete around round brackets and enter insert mode",
    ),
    HelpEntry(
      syntax: "ca[ or ca]",
      description: "Delete around square brackets and enter insert mode",
    ),
    HelpEntry(
      syntax: "ca{ or ca}",
      description: "Delete around curly brackets and enter insert mode",
    ),
    HelpEntry(
      syntax: "cf any",
      description: "Delete characters to the any character and enter insert mode",
    ),
    HelpEntry(
      syntax: "ct any",
      description: "Delete characters until the character and enter insert mode",
    ),
    HelpEntry(syntax: "di\"", description: "Delete the inside of double quotes"),
    HelpEntry(syntax: "di'", description: "Delete the inside of single quotes"),
    HelpEntry(syntax: "diw", description: "Delete the current word"),
    HelpEntry(syntax: "diW", description: "Delete the current WORD"),
    HelpEntry(syntax: "di( or di)", description: "Delete the inside of round brackets"),
    HelpEntry(syntax: "di[ or di]", description: "Delete the inside of square brackets"),
    HelpEntry(syntax: "di{ or di}", description: "Delete the inside of curly brackets"),
    HelpEntry(
      syntax: "da\"", description: "Delete around double quotes (including quotes)"
    ),
    HelpEntry(
      syntax: "da'", description: "Delete around single quotes (including quotes)"
    ),
    HelpEntry(
      syntax: "daw", description: "Delete a word (including surrounding whitespace)"
    ),
    HelpEntry(
      syntax: "daW", description: "Delete a WORD (including surrounding whitespace)"
    ),
    HelpEntry(
      syntax: "da( or da)",
      description: "Delete around round brackets (including brackets)",
    ),
    HelpEntry(
      syntax: "da[ or da]",
      description: "Delete around square brackets (including brackets)",
    ),
    HelpEntry(
      syntax: "da{ or da}",
      description: "Delete around curly brackets (including brackets)",
    ),
    HelpEntry(syntax: "dt any", description: "Delete characters until the character"),
    HelpEntry(syntax: "yiw", description: "Yank the current word"),
    HelpEntry(syntax: "yiW", description: "Yank the current WORD"),
    HelpEntry(syntax: "yi\"", description: "Yank the inside of double quotes"),
    HelpEntry(syntax: "yi'", description: "Yank the inside of single quotes"),
    HelpEntry(syntax: "yi( or yi)", description: "Yank the inside of round brackets"),
    HelpEntry(syntax: "yi[ or yi]", description: "Yank the inside of square brackets"),
    HelpEntry(syntax: "yi{ or yi}", description: "Yank the inside of curly brackets"),
    HelpEntry(
      syntax: "yaw", description: "Yank a word (including surrounding whitespace)"
    ),
    HelpEntry(
      syntax: "yaW", description: "Yank a WORD (including surrounding whitespace)"
    ),
    HelpEntry(syntax: "*", description: "Search forwards for the word under cursor"),
    HelpEntry(syntax: "#", description: "Search backwards for the word under cursor"),
    HelpEntry(
      syntax: "f", description: "Move to next any character on the current line"
    ),
    HelpEntry(
      syntax: "F", description: "Move to previous any character on the current line"
    ),
    HelpEntry(
      syntax: "t",
      description: "Move to the left of the any character on the current line",
    ),
    HelpEntry(
      syntax: "T",
      description: "Move to the right of the back any character on the current line",
    ),
    HelpEntry(syntax: ";", description: "Repeat last f/F/t/T"),
    HelpEntry(syntax: ",", description: "Repeat last f/F/t/T in reverse"),
    HelpEntry(syntax: "Ctrl-w k", description: "Move to the next window"),
    HelpEntry(syntax: "Ctrl-w j", description: "Move to the previous window"),
    HelpEntry(
      syntax: "zt", description: "Scroll the screen so the cursor is at the top"
    ),
    HelpEntry(
      syntax: "zb", description: "Scroll the screen so the cursor is at the bottom"
    ),
    HelpEntry(syntax: "z.", description: "Center the screen on the cursor"),
    HelpEntry(syntax: "zz", description: "Center the screen on the cursor"),
    HelpEntry(syntax: "ZZ", description: "Write current file and exit"),
    HelpEntry(syntax: "ZQ", description: "Same as :q!"),
    HelpEntry(syntax: "Ctrl-w c", description: "Close current window"),
    HelpEntry(syntax: "Ctrl-w +", description: "Increase window height"),
    HelpEntry(syntax: "Ctrl-w -", description: "Decrease window height"),
    HelpEntry(syntax: "Ctrl-w >", description: "Increase window width"),
    HelpEntry(syntax: "Ctrl-w <", description: "Decrease window width"),
    HelpEntry(syntax: "Ctrl-w =", description: "Equalize window sizes"),
    HelpEntry(syntax: "Ctrl-w x", description: "Swap window with next window"),
    HelpEntry(syntax: "/", description: "Search forwards"),
    HelpEntry(syntax: "?", description: "Search backwards"),
    HelpEntry(syntax: "\\r", description: "QuickRun"),
    HelpEntry(syntax: "ga", description: "Show current character info"),
    HelpEntry(syntax: ".", description: "Repeat the last normal mode command"),
    HelpEntry(syntax: "q any", description: "Start recording operations for Macros"),
    HelpEntry(syntax: "q", description: "Stop recoding operations"),
    HelpEntry(syntax: "@ any", description: "Exec a macro"),
    HelpEntry(syntax: "@:", description: "Repeat the last command mode command"),
    HelpEntry(syntax: "K", description: "Hover (LSP)"),
    HelpEntry(syntax: "gc", description: "Goto Declaration (LSP)"),
    HelpEntry(syntax: "gd", description: "Goto Definition (LSP)"),
    HelpEntry(syntax: "gy", description: "Goto Type Definition (LSP)"),
    HelpEntry(syntax: "gi", description: "Goto Implementation (LSP)"),
    HelpEntry(syntax: "gr", description: "References (LSP)"),
    HelpEntry(syntax: "gh", description: "Open Call hierarchy viewer (LSP)"),
    HelpEntry(syntax: "gH", description: "Outgoing call hierarchy (LSP)"),
    HelpEntry(syntax: "gl", description: "Document Link (LSP)"),
    HelpEntry(syntax: "gf", description: "Open URI/file under cursor"),
    HelpEntry(syntax: "Space r", description: "Rename (LSP)"),
    HelpEntry(syntax: "gL", description: "Code Lens (LSP)"),
    HelpEntry(syntax: "zo", description: "Open fold"),
    HelpEntry(syntax: "zc", description: "Close fold"),
    HelpEntry(syntax: "za", description: "Toggle fold"),
    HelpEntry(syntax: "zR", description: "Open all folds"),
    HelpEntry(syntax: "zM", description: "Close all folds"),
    HelpEntry(syntax: "zd", description: "Delete folding lines"),
    HelpEntry(syntax: "zD", description: "Delete all folding lines"),
    HelpEntry(syntax: "Ctrl-s", description: "Selection Range (LSP)"),
    HelpEntry(syntax: "Space o", description: "Document Symbol (LSP)"),
    HelpEntry(syntax: "gt", description: "Switch to the next buffer"),
    HelpEntry(syntax: "gT", description: "Switch to the previous buffer"),
    HelpEntry(syntax: "Ctrl-o", description: "Jump Back (Jumplist)"),
    HelpEntry(syntax: "Ctrl-i", description: "Jump Forward (Jumplist)"),
    HelpEntry(syntax: "mm", description: "Toggle bookmark on current line"),
    HelpEntry(syntax: "mn", description: "Jump to next bookmark"),
    HelpEntry(syntax: "mp", description: "Jump to previous bookmark"),
    HelpEntry(syntax: "mc", description: "Clear all bookmarks in current buffer"),
  ]
)

const BackupModeCommands*: HelpGroup = HelpGroup(
  entries: @[
    HelpEntry(syntax: "j", description: "Go down"),
    HelpEntry(syntax: "k", description: "Go up"),
    HelpEntry(syntax: "gg", description: "Go to the first line"),
    HelpEntry(syntax: "G", description: "Go to the last line"),
    HelpEntry(syntax: "Enter", description: "Open diff"),
    HelpEntry(syntax: "R", description: "Restore backup file"),
    HelpEntry(syntax: "D", description: "Delete backup file"),
    HelpEntry(syntax: "r", description: "Reload backup files"),
  ]
)

const DiffModeCommands*: HelpGroup = HelpGroup(
  entries: @[
    HelpEntry(syntax: "j", description: "Go down"),
    HelpEntry(syntax: "k", description: "Go up"),
    HelpEntry(syntax: "gg", description: "Go to the first line"),
    HelpEntry(syntax: "G", description: "Go to the last line"),
  ]
)

const ReferencesModeCommands*: HelpGroup = HelpGroup(
  entries: @[
    HelpEntry(syntax: "j", description: "Go down"),
    HelpEntry(syntax: "k", description: "Go up"),
    HelpEntry(syntax: "gg", description: "Go to the first line"),
    HelpEntry(syntax: "G", description: "Go to the last line"),
    HelpEntry(syntax: "Enter", description: "Jump to the destination"),
    HelpEntry(syntax: "Esc", description: "Quit References mode"),
  ]
)

const CallHierarchyModeCommands*: HelpGroup = HelpGroup(
  entries: @[
    HelpEntry(syntax: "j", description: "Go down"),
    HelpEntry(syntax: "k", description: "Go up"),
    HelpEntry(syntax: "gg", description: "Go to the first line"),
    HelpEntry(syntax: "G", description: "Go to the last line"),
    HelpEntry(syntax: "Enter", description: "Jump to the destination"),
    HelpEntry(syntax: "i", description: "Incoming call"),
    HelpEntry(syntax: "o", description: "Outgoing call"),
  ]
)

# `syntax` uses the space-separated `any` placeholder that `tokenizeKey`
# normalizes to the canonical `Any key` token, matching the convention
# already used by `yt any` / `q any` / `@ any` entries elsewhere. This lets
# the markdown renderer share `renderKbdHelpGroup` instead of needing a
# Register-specific tokenizer.
const RegisterCommands*: HelpGroup = HelpGroup(
  entries: @[
    HelpEntry(syntax: "\" any yy", description: "Yank a line to a named register"),
    HelpEntry(syntax: "\" any yl", description: "Yank a character to a named register"),
    HelpEntry(syntax: "\" any yw", description: "Yank a word to a named register"),
    HelpEntry(
      syntax: "\" any y}",
      description: "Yank to the next blank line to a named register",
    ),
    HelpEntry(
      syntax: "\" any y{",
      description: "Yank to the previous blank line to a named register",
    ),
    HelpEntry(
      syntax: "\" any p", description: "Paste from a named register after cursor"
    ),
    HelpEntry(
      syntax: "\" any P", description: "Paste from a named register before cursor"
    ),
    HelpEntry(syntax: "\" any dd", description: "Delete a line to a named register"),
    HelpEntry(syntax: "\" any dw", description: "Delete a word to a named register"),
    HelpEntry(
      syntax: "\" any d$", description: "Delete to end of line to a named register"
    ),
    HelpEntry(
      syntax: "\" any d0",
      description: "Delete to beginning of line to a named register",
    ),
    HelpEntry(
      syntax: "\" any dG", description: "Delete to end of file to a named register"
    ),
    HelpEntry(
      syntax: "\" any dgg",
      description: "Delete to beginning of file to a named register",
    ),
    HelpEntry(
      syntax: "\" any d{",
      description: "Delete to the previous blank line to a named register",
    ),
    HelpEntry(
      syntax: "\" any d}",
      description: "Delete to the next blank line to a named register",
    ),
    HelpEntry(syntax: "\" any di any", description: "Delete inside to a named register"),
    HelpEntry(
      syntax: "\" any dh",
      description: "Delete a character before cursor to a named register",
    ),
    HelpEntry(
      syntax: "\" any cl or \" any s",
      description: "Change a character to a named register",
    ),
    HelpEntry(syntax: "\" any ci any", description: "Change inside to a named register"),
  ]
)

# `minWidth: 7` matches the hand-written original, which padded one column
# beyond the longest entry (`d or x` / `Ctrl-a` / ...) for breathing room.
const VisualModeCommands*: HelpGroup = HelpGroup(
  minWidth: 7,
  entries: @[
    HelpEntry(syntax: "d or x", description: "Delete text"),
    HelpEntry(
      syntax: "c", description: "Change (delete selection and enter insert mode)"
    ),
    HelpEntry(syntax: "y", description: "Copy text"),
    HelpEntry(syntax: "r", description: "Replace character"),
    HelpEntry(syntax: "S", description: "Surround selection with character"),
    HelpEntry(syntax: "J", description: "Join lines"),
    HelpEntry(syntax: "u", description: "Convert to lowercase"),
    HelpEntry(syntax: "U", description: "Convert to uppercase"),
    HelpEntry(syntax: ">", description: "Indent"),
    HelpEntry(syntax: "<", description: "Unindent"),
    HelpEntry(syntax: "~", description: "Toggle case of character under cursor"),
    HelpEntry(syntax: "Ctrl-a", description: "Increase number under cursor"),
    HelpEntry(syntax: "Ctrl-x", description: "Decrease number under cursor"),
    HelpEntry(syntax: "I", description: "Insert character, multiple lines"),
    HelpEntry(syntax: "zf", description: "Fold selected lines"),
    HelpEntry(syntax: "Ctrl-s", description: "Selection Range (LSP)"),
    HelpEntry(syntax: "Esc", description: "Go to Normal mode"),
  ],
)

const ReplaceModeCommands*: HelpGroup = HelpGroup(
  entries: @[
    HelpEntry(syntax: "Esc", description: "Go to Normal mode"),
    HelpEntry(syntax: "Backspace", description: "Undo"),
  ]
)

const InsertModeCommands*: HelpGroup = HelpGroup(
  entries: @[
    HelpEntry(
      syntax: "Ctrl-e", description: "Insert the character which is below the cursor"
    ),
    HelpEntry(
      syntax: "Ctrl-y", description: "Insert the character which is above the cursor"
    ),
    HelpEntry(syntax: "Ctrl-i", description: "Insert a Tab"),
    HelpEntry(
      syntax: "Ctrl-h or Backspace",
      description: "Delete the character before the cursor",
    ),
    HelpEntry(syntax: "Ctrl-t", description: "Add an indent in current line"),
    HelpEntry(syntax: "Ctrl-d", description: "Remove an indent in current line"),
    HelpEntry(syntax: "Ctrl-w", description: "Delete the word before the cursor"),
    HelpEntry(
      syntax: "Ctrl-u",
      description: "Delete all characters before the cursor in the current line",
    ),
    HelpEntry(syntax: "Ctrl-r", description: "Signature Help (LSP)"),
    HelpEntry(
      syntax: "Ctrl-o",
      description: "Execute one Normal mode command and return to Insert mode",
    ),
    HelpEntry(syntax: "Esc", description: "Go to Normal mode"),
  ]
)

const TerminalInputCommands*: HelpGroup = HelpGroup(
  entries: @[
    HelpEntry(
      syntax: "Ctrl-\\ Ctrl-n", description: "Switch to Terminal-Normal sub-mode"
    )
  ]
)

# `minWidth: 2` matches the original which padded one column beyond
# the longest entry (`i` / `a` / `:` are all 1 char).
const TerminalNormalCommands*: HelpGroup = HelpGroup(
  minWidth: 2,
  entries: @[
    HelpEntry(syntax: "i", description: "Return to Terminal-Input sub-mode"),
    HelpEntry(syntax: "a", description: "Return to Terminal-Input sub-mode"),
    HelpEntry(syntax: ":", description: "Enter command mode"),
  ],
)

const FilerModeCommands*: HelpGroup = HelpGroup(
  entries: @[
    HelpEntry(syntax: "j", description: "Go down"),
    HelpEntry(syntax: "k", description: "Go up"),
    HelpEntry(syntax: "gg", description: "Go to the first line"),
    HelpEntry(syntax: "G", description: "Go to the last line"),
    HelpEntry(syntax: "l", description: "Enter directory or open file"),
    HelpEntry(syntax: "i", description: "Detail Information"),
    HelpEntry(syntax: ".", description: "Toggle hidden files"),
    HelpEntry(syntax: "D", description: "Delete file"),
    HelpEntry(syntax: "v", description: "Split window and open file or directory"),
    HelpEntry(syntax: "h", description: "Split window horizontally and open file"),
  ]
)

const FileTreeModeCommands*: HelpGroup = HelpGroup(
  entries: @[
    HelpEntry(syntax: "j or Down", description: "Move selection down"),
    HelpEntry(syntax: "k or Up", description: "Move selection up"),
    HelpEntry(syntax: "gg", description: "Move to first item"),
    HelpEntry(syntax: "G", description: "Move to last item"),
    HelpEntry(syntax: "p", description: "Move to parent node"),
    HelpEntry(
      syntax: "Enter", description: "Open file, or toggle expand/collapse directory"
    ),
    HelpEntry(syntax: "o", description: "Open file, or expand directory"),
    HelpEntry(syntax: "l", description: "Open file, or expand directory"),
    HelpEntry(syntax: "x", description: "Collapse directory (or move to parent)"),
    HelpEntry(syntax: "h", description: "Collapse directory (or move to parent)"),
    HelpEntry(syntax: "C", description: "Change root to selected directory"),
    HelpEntry(syntax: "u", description: "Move root up one level"),
    HelpEntry(syntax: "/", description: "Start incremental search"),
    HelpEntry(syntax: "n", description: "Jump to next search match"),
    HelpEntry(syntax: "N", description: "Jump to previous search match"),
    HelpEntry(syntax: ".", description: "Toggle hidden files"),
    HelpEntry(syntax: "R", description: "Refresh tree"),
    HelpEntry(syntax: ":", description: "Enter command mode"),
    HelpEntry(syntax: "Esc", description: "Clear search highlight (press twice)"),
    HelpEntry(syntax: "Ctrl-w w", description: "Move to next window"),
    HelpEntry(syntax: "Ctrl-w p", description: "Move to previous window"),
    HelpEntry(syntax: "Ctrl-w >", description: "Increase window width"),
    HelpEntry(syntax: "Ctrl-w <", description: "Decrease window width"),
  ]
)

const BufferManagerModeCommands*: HelpGroup = HelpGroup(
  entries: @[
    HelpEntry(syntax: "j or Down", description: "Go down"),
    HelpEntry(syntax: "k or Up", description: "Go up"),
    HelpEntry(syntax: "gg", description: "Go to the first buffer"),
    HelpEntry(syntax: "G", description: "Go to the last buffer"),
    HelpEntry(syntax: "Ctrl-d", description: "Half page down"),
    HelpEntry(syntax: "Ctrl-u", description: "Half page up"),
    HelpEntry(syntax: "Enter or o", description: "Open the selected buffer"),
    HelpEntry(syntax: "D", description: "Delete the selected buffer"),
    HelpEntry(syntax: ":", description: "Enter command mode"),
    HelpEntry(syntax: "q or Esc", description: "Close Buffer Manager"),
  ]
)

const BookmarkManagerModeCommands*: HelpGroup = HelpGroup(
  entries: @[
    HelpEntry(syntax: "j or Down", description: "Go down"),
    HelpEntry(syntax: "k or Up", description: "Go up"),
    HelpEntry(syntax: "gg", description: "Go to the first bookmark"),
    HelpEntry(syntax: "G", description: "Go to the last bookmark"),
    HelpEntry(syntax: "Ctrl-d", description: "Half page down"),
    HelpEntry(syntax: "Ctrl-u", description: "Half page up"),
    HelpEntry(syntax: "Enter", description: "Jump to the selected bookmark"),
    HelpEntry(syntax: "D", description: "Delete the selected bookmark"),
    HelpEntry(syntax: ":", description: "Enter command mode"),
    HelpEntry(syntax: "q or Esc", description: "Close Bookmark Manager"),
  ]
)

const DocumentSymbolModeCommands*: HelpGroup = HelpGroup(
  entries: @[
    HelpEntry(syntax: "j or Down", description: "Go down"),
    HelpEntry(syntax: "k or Up", description: "Go up"),
    HelpEntry(syntax: "gg", description: "Go to the first symbol"),
    HelpEntry(syntax: "G", description: "Go to the last symbol"),
    HelpEntry(syntax: "Ctrl-d", description: "Half page down"),
    HelpEntry(syntax: "Ctrl-u", description: "Half page up"),
    HelpEntry(syntax: "Enter", description: "Jump to the selected symbol"),
    HelpEntry(syntax: ":", description: "Enter command mode"),
    HelpEntry(syntax: "q or Esc", description: "Close Document Symbol viewer"),
  ]
)

const ConfigModeCommands*: HelpGroup = HelpGroup(
  entries: @[
    HelpEntry(syntax: "j or Down", description: "Move selection down"),
    HelpEntry(syntax: "k or Up", description: "Move selection up"),
    HelpEntry(syntax: "gg", description: "Go to the first item"),
    HelpEntry(syntax: "G", description: "Go to the last item"),
    HelpEntry(syntax: "Ctrl-d", description: "Half page down"),
    HelpEntry(syntax: "Ctrl-u", description: "Half page up"),
    HelpEntry(
      syntax: "Enter",
      description:
        "Toggle bool, open enum popup, or start editing int/float/string/color",
    ),
    HelpEntry(syntax: "l or Space", description: "Same as Enter"),
    HelpEntry(
      syntax: "Right",
      description: "Cycle enum forward, increment int/float, or toggle bool",
    ),
    HelpEntry(
      syntax: "Left", description: "Cycle enum backward, or decrement int/float"
    ),
    HelpEntry(syntax: "h", description: "Cycle enum backward, or decrement int/float"),
    HelpEntry(syntax: "/", description: "Search forwards"),
    HelpEntry(syntax: "?", description: "Search backwards"),
    HelpEntry(syntax: "n", description: "Jump to next search match"),
    HelpEntry(syntax: "N", description: "Jump to previous search match"),
    HelpEntry(syntax: ":", description: "Enter command mode"),
    HelpEntry(syntax: "Esc", description: "Clear search highlight (press twice)"),
  ]
)

const LogViewerModeCommands*: HelpGroup = HelpGroup(
  entries: @[
    HelpEntry(syntax: "h or Left", description: "Go left"),
    HelpEntry(syntax: "j or Down", description: "Go down"),
    HelpEntry(syntax: "k or Up", description: "Go up"),
    HelpEntry(syntax: "l or Right", description: "Go right"),
    HelpEntry(syntax: "0 or Home", description: "Go to the first character of the line"),
    HelpEntry(syntax: "$ or End", description: "Go to the end of the line"),
    HelpEntry(syntax: "w", description: "Go forwards to the start of a word"),
    HelpEntry(syntax: "b", description: "Go backwards to the start of a word"),
    HelpEntry(syntax: "e", description: "Go forwards to the end of a word"),
    HelpEntry(syntax: "{", description: "Go to the previous blank line"),
    HelpEntry(syntax: "}", description: "Go to the next blank line"),
    HelpEntry(syntax: "gg", description: "Go to the first line"),
    HelpEntry(syntax: "G", description: "Go to the last line"),
    HelpEntry(syntax: "Ctrl-d", description: "Half page down"),
    HelpEntry(syntax: "Ctrl-u", description: "Half page up"),
    HelpEntry(syntax: "Ctrl-f", description: "Page down"),
    HelpEntry(syntax: "Ctrl-b", description: "Page up"),
    HelpEntry(syntax: "/", description: "Search forwards"),
    HelpEntry(syntax: "?", description: "Search backwards"),
    HelpEntry(syntax: "n", description: "Repeat last search forwards"),
    HelpEntry(syntax: "N", description: "Repeat last search backwards"),
    HelpEntry(syntax: "*", description: "Search forwards for the word under cursor"),
    HelpEntry(syntax: "#", description: "Search backwards for the word under cursor"),
    HelpEntry(syntax: "v", description: "Start character-wise Visual selection"),
    HelpEntry(syntax: "V", description: "Start line-wise Visual selection"),
    HelpEntry(syntax: "Ctrl-v", description: "Start block-wise Visual selection"),
    HelpEntry(syntax: "r", description: "Refresh log content"),
    HelpEntry(syntax: ":", description: "Enter command mode"),
    HelpEntry(syntax: "q", description: "Close Log Viewer"),
  ]
)

const RecentFileModeCommands*: HelpGroup = HelpGroup(
  entries: @[
    HelpEntry(syntax: "j or Down", description: "Move selection down"),
    HelpEntry(syntax: "k or Up", description: "Move selection up"),
    HelpEntry(syntax: "gg", description: "Move to the first file"),
    HelpEntry(syntax: "G", description: "Move to the last file"),
    HelpEntry(syntax: "Ctrl-d", description: "Half page down"),
    HelpEntry(syntax: "Ctrl-u", description: "Half page up"),
    HelpEntry(syntax: "Enter", description: "Open the selected file"),
    HelpEntry(syntax: ":", description: "Enter command mode"),
  ]
)

const DebugModeCommands*: HelpGroup = HelpGroup(
  entries: @[
    HelpEntry(syntax: "j or Down", description: "Scroll down"),
    HelpEntry(syntax: "k or Up", description: "Scroll up"),
    HelpEntry(syntax: "g or Home", description: "Go to top"),
    HelpEntry(syntax: "G or End", description: "Go to bottom"),
    HelpEntry(syntax: "Ctrl-d or Page Down", description: "Page down"),
    HelpEntry(syntax: "Ctrl-u or Page Up", description: "Page up"),
    HelpEntry(syntax: "q", description: "Close the debug viewer"),
    HelpEntry(syntax: ":", description: "Enter command mode"),
  ]
)

const ExitingHelpNames =
  @["w", "q", "wq", "q!", "qa!", "wqa", "wqa!", "w!", "wq!", "cq"]

proc boolSetHead(spec: SetOptionSpec): string =
  result = "set " & spec.longName & " / set no" & spec.longName
  if spec.shortName.len > 0:
    result.add " (" & spec.shortName & "/no" & spec.shortName & ")"

proc valueSetHead(spec: SetOptionSpec): string =
  result = "set " & spec.longName & "=number"
  if spec.shortName.len > 0:
    result.add " (" & spec.shortName & ")"

proc valueSetExample(spec: SetOptionSpec): string =
  ## Mirror of the hand-written "e.g. set X=N" / "set X=N.N" forms. Callers
  ## must filter out `sokBool` specs first — bool options have no value form.
  case spec.kind
  of sokInt:
    "set " & spec.longName & "=" & $spec.intExample
  of sokFloat:
    "set " & spec.longName & "=" & $spec.floatExample
  of sokBool:
    raiseAssert "valueSetExample called with bool spec: " & spec.longName

proc renderGroup(g: HelpGroup): string =
  ## Render one blank-line-separated group with per-group left-column alignment.
  var width = g.minWidth
  for e in g.entries:
    if e.syntax.len > width:
      width = e.syntax.len
  for e in g.entries:
    result.add e.syntax.alignLeft(width)
    result.add " - "
    result.add toPlainText(e.description)
    result.add '\n'

proc helpEntriesFor(name: string): seq[HelpEntry] {.compileTime.} =
  ## Look up a command-line spec by name and return its `helpEntries`.
  ## Empty seq if the spec is not found or has no help entries.
  let s = findCommandLineCommand(name)
  if s.isSome:
    s.get.helpEntries
  else:
    @[]

proc renderEntries(entries: seq[HelpEntry]): string {.compileTime.} =
  renderGroup(HelpGroup(entries: entries))

proc renderExitingSection*(): string {.compileTime.} =
  ## The "# Exiting" section body (`:w`, `:q`, ... — one blank-line-less
  ## group, derived from `CommandLineCommandTable` filtered by the
  ## hand-curated `ExitingHelpNames` order).
  var entries: seq[HelpEntry]
  for name in ExitingHelpNames:
    entries.add helpEntriesFor(name)
  renderEntries(entries)

proc renderChangingModesSection*(): string {.compileTime.} =
  ## The "# Changing modes" section body.
  renderGroup(ChangingModesCommands)

proc renderNormalModeSection*(): string {.compileTime.} =
  ## The "# Normal mode" section body.
  renderGroup(NormalModeCommands)

proc renderBackupModeSection*(): string {.compileTime.} =
  ## The "# Backup mode" section body.
  renderGroup(BackupModeCommands)

proc renderDiffModeSection*(): string {.compileTime.} =
  ## The "# Diff mode" section body.
  renderGroup(DiffModeCommands)

proc renderReferencesModeSection*(): string {.compileTime.} =
  ## The "# References mode" section body.
  renderGroup(ReferencesModeCommands)

proc renderCallHierarchyModeSection*(): string {.compileTime.} =
  ## The "# Call hierarchy viewer mode" section body.
  renderGroup(CallHierarchyModeCommands)

proc renderRegisterSection*(): string {.compileTime.} =
  ## The "# Register" section body.
  renderGroup(RegisterCommands)

proc renderVisualModeSection*(): string {.compileTime.} =
  ## The "# Visual mode" section body.
  renderGroup(VisualModeCommands)

proc renderReplaceModeSection*(): string {.compileTime.} =
  ## The "# Replace mode" section body.
  renderGroup(ReplaceModeCommands)

proc renderInsertModeSection*(): string {.compileTime.} =
  ## The "# Insert mode" section body.
  renderGroup(InsertModeCommands)

proc renderTerminalInputSection*(): string {.compileTime.} =
  ## The "## Terminal-Input sub-mode" body (just the key entry,
  ## not the narrative paragraph that precedes it).
  renderGroup(TerminalInputCommands)

proc renderTerminalNormalSection*(): string {.compileTime.} =
  ## The "## Terminal-Normal sub-mode" body.
  renderGroup(TerminalNormalCommands)

proc renderFilerModeSection*(): string {.compileTime.} =
  ## The "# Filer mode" section body.
  renderGroup(FilerModeCommands)

proc renderFileTreeModeSection*(): string {.compileTime.} =
  ## The "# FileTree mode" section body.
  renderGroup(FileTreeModeCommands)

proc renderBufferManagerModeSection*(): string {.compileTime.} =
  ## The "# Buffer manager mode" section body.
  renderGroup(BufferManagerModeCommands)

proc renderBookmarkManagerModeSection*(): string {.compileTime.} =
  ## The "# Bookmark manager mode" section body.
  renderGroup(BookmarkManagerModeCommands)

proc renderDocumentSymbolModeSection*(): string {.compileTime.} =
  ## The "# Document symbol viewer mode" section body.
  renderGroup(DocumentSymbolModeCommands)

proc renderConfigModeSection*(): string {.compileTime.} =
  ## The "# Configuration mode" section body.
  renderGroup(ConfigModeCommands)

proc renderLogViewerModeSection*(): string {.compileTime.} =
  ## The "# Log viewer mode" section body.
  renderGroup(LogViewerModeCommands)

proc renderRecentFileModeSection*(): string {.compileTime.} =
  ## The "# Recent file mode" section body.
  renderGroup(RecentFileModeCommands)

proc renderDebugModeSection*(): string {.compileTime.} =
  ## The "# Debug mode" section body.
  renderGroup(DebugModeCommands)

proc renderCommandModeHead*(): string {.compileTime.} =
  ## "# Command mode" groups that appear *before* the `set` options block.
  ## Each group is built by concatenating `CommandLineSpecialHelp` entries
  ## (for non-alias special syntax like `number`, `! shell command`,
  ## `%s/.../`) and per-name lookups from `CommandLineCommandTable`.
  let groups: seq[seq[HelpEntry]] = @[
    @[CommandLineSpecialHelp.lineNumber, CommandLineSpecialHelp.shellCommand] &
      helpEntriesFor("bg") & helpEntriesFor("man"),
    helpEntriesFor("e") & helpEntriesFor("ene") & helpEntriesFor("new") &
      helpEntriesFor("vnew"),
    @[CommandLineSpecialHelp.substitute] & helpEntriesFor("delete") &
      @[CommandLineSpecialHelp.deleteAll, CommandLineSpecialHelp.deleteRange],
    helpEntriesFor("ls") & helpEntriesFor("bprev") & helpEntriesFor("bnext") &
      helpEntriesFor("bfirst") & helpEntriesFor("blast") & helpEntriesFor("bd") &
      helpEntriesFor("vs") & helpEntriesFor("sp") & helpEntriesFor("only") &
      helpEntriesFor("filetree"),
    helpEntriesFor("theme") & helpEntriesFor("noh") & helpEntriesFor("stripwhitespace"),
  ]
  for i, entries in groups:
    if i > 0:
      result.add '\n'
    result.add renderEntries(entries)

proc renderCommandModeTail*(): string {.compileTime.} =
  ## "# Command mode" groups that appear *after* the `set` options block.
  let groups: seq[seq[HelpEntry]] = @[
    helpEntriesFor("build") & helpEntriesFor("lspfold") & helpEntriesFor("lspformat"),
    helpEntriesFor("log") & helpEntriesFor("lsplog"),
    helpEntriesFor("lsprestart") & helpEntriesFor("lspcallhierarchyincoming") &
      helpEntriesFor("lspcallhierarchyoutgoing"),
    helpEntriesFor("help"),
    helpEntriesFor("putconfigfile"),
    helpEntriesFor("moerc"),
    helpEntriesFor("quickrun"),
    helpEntriesFor("recent"),
    helpEntriesFor("backup"),
    helpEntriesFor("config"),
    helpEntriesFor("debug"),
    helpEntriesFor("jump"),
    helpEntriesFor("terminal"),
    helpEntriesFor("changes"),
    helpEntriesFor("bookmarks"),
    helpEntriesFor("conflictnext") & helpEntriesFor("conflictprev"),
  ]
  for i, entries in groups:
    if i > 0:
      result.add '\n'
    result.add renderEntries(entries)

proc renderSetOptionsSection*(): string {.compileTime.} =
  ## The `set X / set noX (sx/nosx) - desc` block, followed by
  ## `set X=number (sx) - desc; e.g. set X=N` value options. Both blocks
  ## are driven by the canonical `SetOptionTable` from `setting_options`.
  var width = 0
  for spec in SetOptionTable:
    if spec.kind == sokBool:
      let h = boolSetHead(spec)
      if h.len > width:
        width = h.len
  for spec in SetOptionTable:
    if spec.kind != sokBool:
      continue
    result.add boolSetHead(spec).alignLeft(width)
    result.add " - "
    result.add toPlainText(spec.description)
    result.add '\n'

  var vwidth = 0
  for spec in SetOptionTable:
    if spec.kind == sokBool:
      continue
    let h = valueSetHead(spec)
    if h.len > vwidth:
      vwidth = h.len
  for spec in SetOptionTable:
    if spec.kind == sokBool:
      continue
    result.add valueSetHead(spec).alignLeft(vwidth)
    result.add " - "
    result.add toPlainText(spec.description)
    result.add "; e.g. "
    result.add valueSetExample(spec)
    result.add '\n'
