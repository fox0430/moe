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
## `# Changing modes`, `# Normal mode`, `# Visual mode`, `# Replace mode`,
## `# Insert mode`, `# Backup mode`, `# Diff mode`, `# References mode`,
## `# Call hierarchy viewer mode`, `# Filer mode`, and the two
## `# Terminal mode` sub-modes) are built from the corresponding
## `XxxCommands*` `ExCmdHelpGroup` constants. The
## `# Register` section is a flat `seq[string]` (`RegisterPatterns`) because
## its lines have no `- description` part. The
## `# Command mode` subsection is built from `ExCommandGroups`, and the
## `set` options block is built from the canonical `SetOptionTable` defined
## in `setting_options`. Each table is the structured source of truth; help
## text is assembled by the `renderXxxSection` `{.compileTime.}` procs and
## the resulting strings are embedded into `const HelpSentences`, so the
## runtime cost is zero.

import std/strutils

import setting_options
export setting_options

type
  ExCmdHelpEntry* = object ## A single line in the # Command mode section.
    syntax*: string ## Left of the dash, e.g. "e filename" or "%s/keyword1/keyword2/"
    description*: string ## Right of the dash.

  ExCmdHelpGroup* = object
    ## A blank-line-separated subgroup within the # Command mode section.
    entries*: seq[ExCmdHelpEntry]
    minWidth*: int
      ## Minimum left-column width. When 0 (default), the renderer uses
      ## the longest `syntax` in `entries`. Set this when the original
      ## hand-written text pads beyond that natural max (e.g. one extra
      ## trailing space for visual breathing room).

const ExitingCommands*: ExCmdHelpGroup = ExCmdHelpGroup(
  entries: @[
    ExCmdHelpEntry(syntax: ":w", description: "Write file"),
    ExCmdHelpEntry(syntax: ":q", description: "Quit"),
    ExCmdHelpEntry(syntax: ":wq", description: "Write and quit"),
    ExCmdHelpEntry(syntax: ":q!", description: "Force quit"),
    ExCmdHelpEntry(syntax: ":qa!", description: "Quit all windows"),
    ExCmdHelpEntry(syntax: ":wqa", description: "Write and quit all windows"),
    ExCmdHelpEntry(syntax: ":wqa!", description: "Force quit all windows"),
    ExCmdHelpEntry(syntax: ":w!", description: "Force write"),
    ExCmdHelpEntry(syntax: ":wq!", description: "Force write and quit window"),
    ExCmdHelpEntry(syntax: ":cq", description: "Quit with non-zero exit code"),
  ]
)

const ChangingModesCommands*: ExCmdHelpGroup = ExCmdHelpGroup(
  entries: @[
    ExCmdHelpEntry(syntax: "v", description: "Visual mode"),
    ExCmdHelpEntry(syntax: "Ctrl-v", description: "Visual block mode"),
    ExCmdHelpEntry(syntax: "V", description: "Visual line mode"),
    ExCmdHelpEntry(syntax: "r", description: "Replace mode"),
    ExCmdHelpEntry(syntax: "i", description: "Insert mode"),
    ExCmdHelpEntry(syntax: "o", description: "Insert a new line and start insert mode"),
    ExCmdHelpEntry(
      syntax: "a", description: "Append after the cursor and start insert mode"
    ),
    ExCmdHelpEntry(syntax: "I", description: "Same as ^i"),
    ExCmdHelpEntry(syntax: "A", description: "Same as $a"),
  ]
)

const NormalModeCommands*: ExCmdHelpGroup = ExCmdHelpGroup(
  entries: @[
    ExCmdHelpEntry(syntax: "h", description: "Go left"),
    ExCmdHelpEntry(syntax: "j", description: "Go down"),
    ExCmdHelpEntry(syntax: "k", description: "Go up"),
    ExCmdHelpEntry(syntax: "l", description: "Go right"),
    ExCmdHelpEntry(syntax: "w", description: "Go forwards to the start of a word"),
    ExCmdHelpEntry(syntax: "e", description: "Go forwards to the end of a word"),
    ExCmdHelpEntry(syntax: "ge", description: "Go backwards to the end of a word"),
    ExCmdHelpEntry(syntax: "b", description: "Go backwards to the start of a word"),
    ExCmdHelpEntry(syntax: "r", description: "Replace a character at the cursor"),
    ExCmdHelpEntry(syntax: "Page Up", description: "Page Up"),
    ExCmdHelpEntry(syntax: "Page Down", description: "Page Down"),
    ExCmdHelpEntry(syntax: "gg", description: "Go to the first line"),
    ExCmdHelpEntry(
      syntax: "g_", description: "Go to the last non-blank character of the line"
    ),
    ExCmdHelpEntry(syntax: "g;", description: "Go to the previous change position"),
    ExCmdHelpEntry(syntax: "g,", description: "Go to the next change position"),
    ExCmdHelpEntry(syntax: "G", description: "Go to the last line"),
    ExCmdHelpEntry(syntax: "0", description: "Go to the first character of the line"),
    ExCmdHelpEntry(syntax: "$", description: "Go to the end of the line"),
    ExCmdHelpEntry(
      syntax: "^", description: "Go to the first non-blank character of the line"
    ),
    ExCmdHelpEntry(syntax: "{", description: "Go to the previous blank line"),
    ExCmdHelpEntry(syntax: "}", description: "Go to the next blank line"),
    ExCmdHelpEntry(syntax: "H", description: "Move to the top line of the screen"),
    ExCmdHelpEntry(syntax: "M", description: "Move to the center line of the screen"),
    ExCmdHelpEntry(syntax: "L", description: "Move to the bottom line of the screen"),
    ExCmdHelpEntry(syntax: "Ctrl-w", description: "Half Page Down"),
    ExCmdHelpEntry(syntax: "Ctrl-d", description: "Half Page Up"),
    ExCmdHelpEntry(syntax: "%", description: "Move to matching pair of paren"),
    ExCmdHelpEntry(syntax: "d$ or D", description: "Delete until the end of the line"),
    ExCmdHelpEntry(syntax: "yy or Y", description: "Copy a line"),
    ExCmdHelpEntry(syntax: "y{", description: "Yank to the previous blank line"),
    ExCmdHelpEntry(syntax: "y}", description: "Yank to the next blank line"),
    ExCmdHelpEntry(syntax: "yl", description: "Yank a character"),
    ExCmdHelpEntry(syntax: "yt any", description: "Yank characters to a any character"),
    ExCmdHelpEntry(syntax: "p", description: "Paste the clipboard"),
    ExCmdHelpEntry(syntax: "n", description: "Search forwards"),
    ExCmdHelpEntry(
      syntax: "gn", description: "Go to next search match and select it visually"
    ),
    ExCmdHelpEntry(
      syntax: "gN", description: "Go to previous search match and select it visually"
    ),
    ExCmdHelpEntry(syntax: "dgn", description: "Delete next search match"),
    ExCmdHelpEntry(syntax: "dgN", description: "Delete previous search match"),
    ExCmdHelpEntry(syntax: "]c", description: "Jump to next git change hunk"),
    ExCmdHelpEntry(syntax: "[c", description: "Jump to previous git change hunk"),
    ExCmdHelpEntry(syntax: "]x", description: "Jump to next git merge conflict block"),
    ExCmdHelpEntry(
      syntax: "[x", description: "Jump to previous git merge conflict block"
    ),
    ExCmdHelpEntry(syntax: ":", description: "Start command mode"),
    ExCmdHelpEntry(syntax: "u", description: "Undo"),
    ExCmdHelpEntry(syntax: "Ctrl-r", description: "Redo"),
    ExCmdHelpEntry(syntax: ">", description: "Indent"),
    ExCmdHelpEntry(syntax: "<", description: "Unindent"),
    ExCmdHelpEntry(syntax: "==", description: "Auto indent"),
    ExCmdHelpEntry(syntax: "dd", description: "Delete a line"),
    ExCmdHelpEntry(syntax: "x", description: "Delete current character"),
    ExCmdHelpEntry(
      syntax: "X or dh", description: "Delete the character before the cursor"
    ),
    ExCmdHelpEntry(
      syntax: "S or cc",
      description: "Delete the characters in the current line and start insert mode",
    ),
    ExCmdHelpEntry(
      syntax: "s or cl",
      description: "Delete the current character and enter insert mode",
    ),
    ExCmdHelpEntry(
      syntax: "ci\"",
      description: "Delete the inside of double quotes and enter insert mode",
    ),
    ExCmdHelpEntry(
      syntax: "ci'",
      description: "Delete the inside of single quotes and enter insert mode",
    ),
    ExCmdHelpEntry(
      syntax: "ciw", description: "Delete the current word and enter insert mode"
    ),
    ExCmdHelpEntry(
      syntax: "ciW", description: "Delete the current WORD and enter insert mode"
    ),
    ExCmdHelpEntry(
      syntax: "ci( or ci)",
      description: "Delete the inside of round brackets and enter insert mode",
    ),
    ExCmdHelpEntry(
      syntax: "ci[ or ci]",
      description: "Delete the inside of square brackets and enter insert mode",
    ),
    ExCmdHelpEntry(
      syntax: "ci{ or ci}",
      description: "Delete the inside of curly brackets and enter insert mode",
    ),
    ExCmdHelpEntry(
      syntax: "ca\"", description: "Delete around double quotes and enter insert mode"
    ),
    ExCmdHelpEntry(
      syntax: "ca'", description: "Delete around single quotes and enter insert mode"
    ),
    ExCmdHelpEntry(
      syntax: "caw",
      description: "Delete a word (with surrounding whitespace) and enter insert mode",
    ),
    ExCmdHelpEntry(
      syntax: "caW",
      description: "Delete a WORD (with surrounding whitespace) and enter insert mode",
    ),
    ExCmdHelpEntry(
      syntax: "ca( or ca)",
      description: "Delete around round brackets and enter insert mode",
    ),
    ExCmdHelpEntry(
      syntax: "ca[ or ca]",
      description: "Delete around square brackets and enter insert mode",
    ),
    ExCmdHelpEntry(
      syntax: "ca{ or ca}",
      description: "Delete around curly brackets and enter insert mode",
    ),
    ExCmdHelpEntry(
      syntax: "cf any",
      description: "Delete characters to the any character and enter insert mode",
    ),
    ExCmdHelpEntry(
      syntax: "ct any",
      description: "Delete characters until the character and enter insert mode",
    ),
    ExCmdHelpEntry(syntax: "di\"", description: "Delete the inside of double quotes"),
    ExCmdHelpEntry(syntax: "di'", description: "Delete the inside of single quotes"),
    ExCmdHelpEntry(syntax: "diw", description: "Delete the current word"),
    ExCmdHelpEntry(syntax: "diW", description: "Delete the current WORD"),
    ExCmdHelpEntry(
      syntax: "di( or di)", description: "Delete the inside of round brackets"
    ),
    ExCmdHelpEntry(
      syntax: "di[ or di]", description: "Delete the inside of square brackets"
    ),
    ExCmdHelpEntry(
      syntax: "di{ or di}", description: "Delete the inside of curly brackets"
    ),
    ExCmdHelpEntry(
      syntax: "da\"", description: "Delete around double quotes (including quotes)"
    ),
    ExCmdHelpEntry(
      syntax: "da'", description: "Delete around single quotes (including quotes)"
    ),
    ExCmdHelpEntry(
      syntax: "daw", description: "Delete a word (including surrounding whitespace)"
    ),
    ExCmdHelpEntry(
      syntax: "daW", description: "Delete a WORD (including surrounding whitespace)"
    ),
    ExCmdHelpEntry(
      syntax: "da( or da)",
      description: "Delete around round brackets (including brackets)",
    ),
    ExCmdHelpEntry(
      syntax: "da[ or da]",
      description: "Delete around square brackets (including brackets)",
    ),
    ExCmdHelpEntry(
      syntax: "da{ or da}",
      description: "Delete around curly brackets (including brackets)",
    ),
    ExCmdHelpEntry(
      syntax: "dt any", description: "Delete characters until the character"
    ),
    ExCmdHelpEntry(syntax: "yiw", description: "Yank the current word"),
    ExCmdHelpEntry(syntax: "yiW", description: "Yank the current WORD"),
    ExCmdHelpEntry(syntax: "yi\"", description: "Yank the inside of double quotes"),
    ExCmdHelpEntry(syntax: "yi'", description: "Yank the inside of single quotes"),
    ExCmdHelpEntry(
      syntax: "yi( or yi)", description: "Yank the inside of round brackets"
    ),
    ExCmdHelpEntry(
      syntax: "yi[ or yi]", description: "Yank the inside of square brackets"
    ),
    ExCmdHelpEntry(
      syntax: "yi{ or yi}", description: "Yank the inside of curly brackets"
    ),
    ExCmdHelpEntry(
      syntax: "yaw", description: "Yank a word (including surrounding whitespace)"
    ),
    ExCmdHelpEntry(
      syntax: "yaW", description: "Yank a WORD (including surrounding whitespace)"
    ),
    ExCmdHelpEntry(
      syntax: "*", description: "Search forwards for the word under cursor"
    ),
    ExCmdHelpEntry(
      syntax: "#", description: "Search backwards for the word under cursor"
    ),
    ExCmdHelpEntry(
      syntax: "f", description: "Move to next any character on the current line"
    ),
    ExCmdHelpEntry(
      syntax: "F", description: "Move to previous any character on the current line"
    ),
    ExCmdHelpEntry(
      syntax: "t",
      description: "Move to the left of the any character on the current line",
    ),
    ExCmdHelpEntry(
      syntax: "T",
      description: "Move to the right of the back any character on the current line",
    ),
    ExCmdHelpEntry(syntax: "Ctrl-w k", description: "Move to the next window"),
    ExCmdHelpEntry(syntax: "Ctrl-w j", description: "Move to the previous window"),
    ExCmdHelpEntry(
      syntax: "zt", description: "Scroll the screen so the cursor is at the top"
    ),
    ExCmdHelpEntry(
      syntax: "zb", description: "Scroll the screen so the cursor is at the bottom"
    ),
    ExCmdHelpEntry(syntax: "z.", description: "Center the screen on the cursor"),
    ExCmdHelpEntry(syntax: "ZZ", description: "Write current file and exit"),
    ExCmdHelpEntry(syntax: "ZQ", description: "Same as :q!"),
    ExCmdHelpEntry(syntax: "Ctrl-w c", description: "Close current window"),
    ExCmdHelpEntry(syntax: "Ctrl-w +", description: "Increase window height"),
    ExCmdHelpEntry(syntax: "Ctrl-w -", description: "Decrease window height"),
    ExCmdHelpEntry(syntax: "Ctrl-w >", description: "Increase window width"),
    ExCmdHelpEntry(syntax: "Ctrl-w <", description: "Decrease window width"),
    ExCmdHelpEntry(syntax: "Ctrl-w =", description: "Equalize window sizes"),
    ExCmdHelpEntry(syntax: "Ctrl-w x", description: "Swap window with next window"),
    ExCmdHelpEntry(syntax: "/", description: "Search forwards"),
    ExCmdHelpEntry(syntax: "?", description: "Search backwards"),
    ExCmdHelpEntry(syntax: "\\r", description: "QuickRun"),
    ExCmdHelpEntry(syntax: "ga", description: "Show current character info"),
    ExCmdHelpEntry(syntax: ".", description: "Repeat the last normal mode command"),
    ExCmdHelpEntry(
      syntax: "q any", description: "Start recording operations for Macros"
    ),
    ExCmdHelpEntry(syntax: "q", description: "Stop recoding operations"),
    ExCmdHelpEntry(syntax: "@ any", description: "Exec a macro"),
    ExCmdHelpEntry(syntax: "@:", description: "Repeat the last command mode command"),
    ExCmdHelpEntry(syntax: "K", description: "Hover (LSP)"),
    ExCmdHelpEntry(syntax: "gc", description: "Goto Declaration (LSP)"),
    ExCmdHelpEntry(syntax: "gd", description: "Goto Definition (LSP)"),
    ExCmdHelpEntry(syntax: "gy", description: "Goto Type Definition (LSP)"),
    ExCmdHelpEntry(syntax: "gi", description: "Goto Implementation (LSP)"),
    ExCmdHelpEntry(syntax: "gr", description: "References (LSP)"),
    ExCmdHelpEntry(syntax: "gh", description: "Open Call hierarchy viewer (LSP)"),
    ExCmdHelpEntry(syntax: "gl", description: "Document Link (LSP)"),
    ExCmdHelpEntry(syntax: "gf", description: "Open URI/file under cursor"),
    ExCmdHelpEntry(syntax: "Space r", description: "Rename (LSP)"),
    ExCmdHelpEntry(syntax: "\\ r", description: "Code Lens (LSP)"),
    ExCmdHelpEntry(syntax: "zd", description: "Delete folding lines"),
    ExCmdHelpEntry(syntax: "zD", description: "Delete all folding lines"),
    ExCmdHelpEntry(syntax: "Ctrl-s", description: "Selection Range (LSP)"),
    ExCmdHelpEntry(syntax: "Space o", description: "Document Symbol (LSP)"),
    ExCmdHelpEntry(syntax: "gt", description: "Switch to the next buffer"),
    ExCmdHelpEntry(syntax: "gT", description: "Switch to the previous buffer"),
    ExCmdHelpEntry(syntax: "Ctrl-o", description: "Jump Back (Jumplist)"),
    ExCmdHelpEntry(syntax: "Ctrl-i", description: "Jump Forward (Jumplist)"),
    ExCmdHelpEntry(syntax: "mm", description: "Toggle bookmark on current line"),
    ExCmdHelpEntry(syntax: "mn", description: "Jump to next bookmark"),
    ExCmdHelpEntry(syntax: "mp", description: "Jump to previous bookmark"),
    ExCmdHelpEntry(syntax: "mc", description: "Clear all bookmarks in current buffer"),
  ]
)

const BackupModeCommands*: ExCmdHelpGroup = ExCmdHelpGroup(
  entries: @[
    ExCmdHelpEntry(syntax: "j", description: "Go down"),
    ExCmdHelpEntry(syntax: "k", description: "Go up"),
    ExCmdHelpEntry(syntax: "gg", description: "Go to the first line"),
    ExCmdHelpEntry(syntax: "G", description: "Go to the last line"),
    ExCmdHelpEntry(syntax: "Enter", description: "Open diff"),
    ExCmdHelpEntry(syntax: "R", description: "Restore backup file"),
    ExCmdHelpEntry(syntax: "D", description: "Delete backup file"),
    ExCmdHelpEntry(syntax: "r", description: "Reload backup files"),
  ]
)

const DiffModeCommands*: ExCmdHelpGroup = ExCmdHelpGroup(
  entries: @[
    ExCmdHelpEntry(syntax: "j", description: "Go down"),
    ExCmdHelpEntry(syntax: "k", description: "Go up"),
    ExCmdHelpEntry(syntax: "gg", description: "Go to the first line"),
    ExCmdHelpEntry(syntax: "G", description: "Go to the last line"),
  ]
)

const ReferencesModeCommands*: ExCmdHelpGroup = ExCmdHelpGroup(
  entries: @[
    ExCmdHelpEntry(syntax: "j", description: "Go down"),
    ExCmdHelpEntry(syntax: "k", description: "Go up"),
    ExCmdHelpEntry(syntax: "gg", description: "Go to the first line"),
    ExCmdHelpEntry(syntax: "G", description: "Go to the last line"),
    ExCmdHelpEntry(syntax: "Enter", description: "Jump to the destination"),
    ExCmdHelpEntry(syntax: "Esc", description: "Quit References mode"),
  ]
)

const CallHierarchyModeCommands*: ExCmdHelpGroup = ExCmdHelpGroup(
  entries: @[
    ExCmdHelpEntry(syntax: "j", description: "Go down"),
    ExCmdHelpEntry(syntax: "k", description: "Go up"),
    ExCmdHelpEntry(syntax: "gg", description: "Go to the first line"),
    ExCmdHelpEntry(syntax: "G", description: "Go to the last line"),
    ExCmdHelpEntry(syntax: "Enter", description: "Jump to the destination"),
    ExCmdHelpEntry(syntax: "i", description: "Incoming call"),
    ExCmdHelpEntry(syntax: "o", description: "Outgoing call"),
  ]
)

const RegisterPatterns*: seq[string] = @[
  "\"-any key-yy", "\"-any key-yl", "\"-any key-yw", "\"-any key-y}", "\"-any key-y{",
  "\"-any key-p", "\"-any key-P", "\"-any key-dd", "\"-any key-dw", "\"-any key-d$",
  "\"-any key-d0", "\"-any key-dG", "\"-any key-dgg", "\"-any key-d{", "\"-any key-d}",
  "\"-any key-di-any key", "\"-any key-dh", "\"-any key-cl", "\"-any key-s",
  "\"-any key-ci-any key",
]

# `minWidth: 7` matches the hand-written original, which padded one column
# beyond the longest entry (`d or x` / `Ctrl-a` / ...) for breathing room.
const VisualModeCommands*: ExCmdHelpGroup = ExCmdHelpGroup(
  minWidth: 7,
  entries: @[
    ExCmdHelpEntry(syntax: "d or x", description: "Delete text"),
    ExCmdHelpEntry(syntax: "y", description: "Copy text"),
    ExCmdHelpEntry(syntax: "r", description: "Replace character"),
    ExCmdHelpEntry(syntax: "S", description: "Surround selection with character"),
    ExCmdHelpEntry(syntax: "J", description: "Join lines"),
    ExCmdHelpEntry(syntax: "u", description: "Convert to lowercase"),
    ExCmdHelpEntry(syntax: "U", description: "Convert to uppercase"),
    ExCmdHelpEntry(syntax: ">", description: "Indent"),
    ExCmdHelpEntry(syntax: "<", description: "Unindent"),
    ExCmdHelpEntry(syntax: "~", description: "Toggle case of character under cursor"),
    ExCmdHelpEntry(syntax: "Ctrl-a", description: "Increase number under cursor"),
    ExCmdHelpEntry(syntax: "Ctrl-x", description: "Decrease number under cursor"),
    ExCmdHelpEntry(syntax: "I", description: "Insert character, multiple lines"),
    ExCmdHelpEntry(syntax: "zf", description: "Fold selected lines"),
    ExCmdHelpEntry(syntax: "Ctrl-s", description: "Selection Range (LSP)"),
    ExCmdHelpEntry(syntax: "Esc", description: "Go to Normal mode"),
  ],
)

const ReplaceModeCommands*: ExCmdHelpGroup = ExCmdHelpGroup(
  entries: @[
    ExCmdHelpEntry(syntax: "Esc", description: "Go to Normal mode"),
    ExCmdHelpEntry(syntax: "Backspace", description: "Undo"),
  ]
)

const InsertModeCommands*: ExCmdHelpGroup = ExCmdHelpGroup(
  entries: @[
    ExCmdHelpEntry(
      syntax: "Ctrl-e", description: "Insert the character which is below the cursor"
    ),
    ExCmdHelpEntry(
      syntax: "Ctrl-y", description: "Insert the character which is above the cursor"
    ),
    ExCmdHelpEntry(syntax: "Ctrl-i", description: "Insert a Tab"),
    ExCmdHelpEntry(
      syntax: "Ctrl-h or Backspace",
      description: "Delete the character before the cursor",
    ),
    ExCmdHelpEntry(syntax: "Ctrl-t", description: "Add an indent in current line"),
    ExCmdHelpEntry(syntax: "Ctrl-d", description: "Remove an indent in current line"),
    ExCmdHelpEntry(syntax: "Ctrl-w", description: "Delete the word before the cursor"),
    ExCmdHelpEntry(
      syntax: "Ctrl-u",
      description: "Delete all characters before the cursor in the current line",
    ),
    ExCmdHelpEntry(syntax: "Ctrl-r", description: "Signature Help (LSP)"),
    ExCmdHelpEntry(
      syntax: "Ctrl-o",
      description: "Execute one Normal mode command and return to Insert mode",
    ),
    ExCmdHelpEntry(syntax: "Esc", description: "Go to Normal mode"),
  ]
)

const TerminalInputCommands*: ExCmdHelpGroup = ExCmdHelpGroup(
  entries: @[
    ExCmdHelpEntry(
      syntax: "Ctrl-\\ Ctrl-n", description: "Switch to Terminal-Normal sub-mode"
    )
  ]
)

# `minWidth: 2` matches the original which padded one column beyond
# the longest entry (`i` / `a` / `:` are all 1 char).
const TerminalNormalCommands*: ExCmdHelpGroup = ExCmdHelpGroup(
  minWidth: 2,
  entries: @[
    ExCmdHelpEntry(syntax: "i", description: "Return to Terminal-Input sub-mode"),
    ExCmdHelpEntry(syntax: "a", description: "Return to Terminal-Input sub-mode"),
    ExCmdHelpEntry(syntax: ":", description: "Enter command mode"),
  ],
)

const FilerModeCommands*: ExCmdHelpGroup = ExCmdHelpGroup(
  entries: @[
    ExCmdHelpEntry(syntax: "j", description: "Go down"),
    ExCmdHelpEntry(syntax: "k", description: "Go up"),
    ExCmdHelpEntry(syntax: "gg", description: "Go to the first line"),
    ExCmdHelpEntry(syntax: "G", description: "Go to the last line"),
    ExCmdHelpEntry(syntax: "i", description: "Detail Information"),
    ExCmdHelpEntry(syntax: "D", description: "Delete file"),
    ExCmdHelpEntry(syntax: "v", description: "Split window and open file or directory"),
  ]
)

const ExCommandGroups*: seq[ExCmdHelpGroup] = @[
  ExCmdHelpGroup(
    entries: @[
      ExCmdHelpEntry(syntax: "number", description: "Jump to line number; e.g. :10"),
      ExCmdHelpEntry(syntax: "! shell command", description: "Shell command execution"),
      ExCmdHelpEntry(
        syntax: "bg",
        description: "Pause the editor and show the recent terminal output",
      ),
      ExCmdHelpEntry(
        syntax: "man arguments",
        description: "Show the given UNIX manual page, if available; e.g. :man man",
      ),
    ]
  ),
  ExCmdHelpGroup(
    entries: @[
      ExCmdHelpEntry(syntax: "e filename", description: "Open file"),
      ExCmdHelpEntry(
        syntax: "e", description: "Reload current file (error if unsaved changes)"
      ),
      ExCmdHelpEntry(
        syntax: "e!", description: "Force reload current file (discard unsaved changes)"
      ),
      ExCmdHelpEntry(
        syntax: "e! filename", description: "Open file (discard unsaved changes)"
      ),
      ExCmdHelpEntry(syntax: "ene", description: "Create a new empty buffer"),
      ExCmdHelpEntry(
        syntax: "new",
        description: "Create a new empty buffer in a horizontally split window",
      ),
      ExCmdHelpEntry(
        syntax: "vnew",
        description: "Create a new empty buffer in a vertically split window",
      ),
    ]
  ),
  ExCmdHelpGroup(
    entries: @[
      ExCmdHelpEntry(
        syntax: "%s/keyword1/keyword2/", description: "Replace text (normal mode only)"
      ),
      ExCmdHelpEntry(
        syntax: "delete", description: "Delete current line and copy to register"
      ),
      ExCmdHelpEntry(syntax: "%d", description: "Delete all lines and copy to register"),
      ExCmdHelpEntry(
        syntax: "1,10d", description: "Delete lines in range and copy to register"
      ),
    ]
  ),
  ExCmdHelpGroup(
    entries: @[
      ExCmdHelpEntry(syntax: "ls", description: "Display all buffers"),
      ExCmdHelpEntry(syntax: "bprev", description: "Switch to the previous buffer"),
      ExCmdHelpEntry(syntax: "bnext", description: "Switch to the next buffer"),
      ExCmdHelpEntry(syntax: "bfirst", description: "Switch to the first buffer"),
      ExCmdHelpEntry(syntax: "blast", description: "Switch to the last buffer"),
      ExCmdHelpEntry(syntax: "bd or bd number", description: "Delete buffer"),
      ExCmdHelpEntry(syntax: "vs", description: "Vertical split window"),
      ExCmdHelpEntry(
        syntax: "vs filename", description: "Open in a vertical split window"
      ),
      ExCmdHelpEntry(syntax: "sp", description: "Horizontal split window"),
      ExCmdHelpEntry(
        syntax: "sp filename", description: "Open in a horizontal split window"
      ),
      ExCmdHelpEntry(syntax: "only", description: "Close all other windows"),
      ExCmdHelpEntry(syntax: "filetree", description: "Toggle FileTree sidebar"),
      ExCmdHelpEntry(
        syntax: "filetree path",
        description: "Toggle FileTree sidebar with specified root path",
      ),
    ]
  ),
  ExCmdHelpGroup(
    entries: @[
      ExCmdHelpEntry(
        syntax: "theme themeName",
        description: "Change color theme; for example theme dark",
      ),
      ExCmdHelpEntry(syntax: "noh", description: "Turn off search highlights"),
      ExCmdHelpEntry(syntax: "stripwhitespace", description: "Delete trailing spaces"),
    ]
  ),
]

const ExCommandTrailingGroups*: seq[ExCmdHelpGroup] = @[
  ## Groups that appear after the `set` options block.
  ExCmdHelpGroup(
    entries: @[
      ExCmdHelpEntry(syntax: "build", description: "Build the current buffer"),
      ExCmdHelpEntry(syntax: "lspfold", description: "LSP Folding Range"),
      ExCmdHelpEntry(syntax: "lspformat", description: "LSP Document Formatting"),
    ]
  ),
  ExCmdHelpGroup(
    entries: @[
      ExCmdHelpEntry(syntax: "log", description: "Open a log viewer for editor log"),
      ExCmdHelpEntry(syntax: "lsplog", description: "Open a log viewer for LSP log"),
    ]
  ),
  ExCmdHelpGroup(
    entries: @[
      ExCmdHelpEntry(
        syntax: "lsprestart", description: "Restart the current LSP server"
      ),
      ExCmdHelpEntry(
        syntax: "lspcallhierarchyincoming",
        description: "Show incoming calls (callers) at cursor",
      ),
      ExCmdHelpEntry(
        syntax: "lspcallhierarchyoutgoing",
        description: "Show outgoing calls (callees) at cursor",
      ),
    ]
  ),
  ExCmdHelpGroup(
    entries: @[ExCmdHelpEntry(syntax: "help", description: "Open this help")]
  ),
  ExCmdHelpGroup(
    entries: @[
      ExCmdHelpEntry(
        syntax: "putconfigfile",
        description: "Put a sample configuration file in ~/.config/moe",
      )
    ]
  ),
  ExCmdHelpGroup(
    entries: @[
      ExCmdHelpEntry(
        syntax: "moerc",
        description: "Open the configuration file (moerc.toml) for editing",
      )
    ]
  ),
  ExCmdHelpGroup(
    entries: @[ExCmdHelpEntry(syntax: "quickrun", description: "Quick run")]
  ),
  ExCmdHelpGroup(
    entries: @[
      ExCmdHelpEntry(
        syntax: "recent",
        description: "Open recent file selection mode (Only supported on Linux)",
      )
    ]
  ),
  ExCmdHelpGroup(
    entries:
      @[ExCmdHelpEntry(syntax: "backup", description: "Open backup file manager")]
  ),
  ExCmdHelpGroup(
    entries: @[ExCmdHelpEntry(syntax: "config", description: "Open configuration mode")]
  ),
  ExCmdHelpGroup(
    entries: @[ExCmdHelpEntry(syntax: "debug", description: "Open debug mode")]
  ),
  ExCmdHelpGroup(
    entries: @[ExCmdHelpEntry(syntax: "jump", description: "Open Jump list viewer")]
  ),
  ExCmdHelpGroup(
    entries: @[
      ExCmdHelpEntry(
        syntax: "terminal", description: "Open terminal emulator (default shell)"
      ),
      ExCmdHelpEntry(
        syntax: "terminal command", description: "Run command in terminal emulator"
      ),
    ]
  ),
  ExCmdHelpGroup(
    entries: @[ExCmdHelpEntry(syntax: "changes", description: "Show Change list")]
  ),
  ExCmdHelpGroup(
    entries: @[ExCmdHelpEntry(syntax: "bookmarks", description: "Show bookmark list")]
  ),
  ExCmdHelpGroup(
    entries: @[
      ExCmdHelpEntry(
        syntax: "conflictnext", description: "Jump to next git merge conflict block"
      ),
      ExCmdHelpEntry(
        syntax: "conflictprev", description: "Jump to previous git merge conflict block"
      ),
    ]
  ),
]

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

proc renderGroup(g: ExCmdHelpGroup): string =
  ## Render one blank-line-separated group with per-group left-column alignment.
  var width = g.minWidth
  for e in g.entries:
    if e.syntax.len > width:
      width = e.syntax.len
  for e in g.entries:
    result.add e.syntax.alignLeft(width)
    result.add " - "
    result.add e.description
    result.add '\n'

proc renderExitingSection*(): string {.compileTime.} =
  ## The "# Exiting" section body (`:w`, `:q`, ... — one blank-line-less group).
  renderGroup(ExitingCommands)

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
  ## The "# Register" section body. Patterns are emitted one per line with
  ## no `key - description` form — they are syntax-only documentation.
  for p in RegisterPatterns:
    result.add p
    result.add '\n'

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

proc renderExCommandHead*(): string {.compileTime.} =
  ## "# Command mode" groups that appear *before* the `set` options block.
  for i, g in ExCommandGroups:
    if i > 0:
      result.add '\n'
    result.add renderGroup(g)

proc renderExCommandTail*(): string {.compileTime.} =
  ## "# Command mode" groups that appear *after* the `set` options block.
  for i, g in ExCommandTrailingGroups:
    if i > 0:
      result.add '\n'
    result.add renderGroup(g)

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
    result.add spec.description
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
    result.add spec.description
    result.add "; e.g. "
    result.add valueSetExample(spec)
    result.add '\n'
