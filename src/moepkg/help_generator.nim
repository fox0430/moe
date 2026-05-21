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
## The "# Command mode" subsection of `HelpSentences` is built from
## `ExCommandGroups`, and the `set` options block is built from
## `BoolSetOptions` / `ValueSetOptions`. Each table is the structured source
## of truth; help text is assembled by `renderExCommandSection` /
## `renderSetOptionsSection` at compile time, so the runtime cost is zero
## and the resulting strings can be embedded into `const HelpSentences`.

import std/strutils

type
  ExCmdHelpEntry* = object ## A single line in the # Command mode section.
    syntax*: string ## Left of the dash, e.g. "e filename" or "%s/keyword1/keyword2/"
    description*: string ## Right of the dash.

  ExCmdHelpGroup* = object
    ## A blank-line-separated subgroup within the # Command mode section.
    entries*: seq[ExCmdHelpEntry]

  SetOptHelpEntry* = object
    longName*: string
    shortName*: string ## "" if no short alias.
    description*: string ## Combined "Show/hide …" style description.

  ValueSetOptHelpEntry* = object
    longName*: string
    shortName*: string ## "" if no short alias.
    description*: string ## Combined description, e.g. "Change scrollbar width".
    example*: string ## Example value form, e.g. "set scrollbarwidth=2".

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

const BoolSetOptions*: seq[SetOptHelpEntry] = @[
  SetOptHelpEntry(
    longName: "number", shortName: "nu", description: "Show/hide line numbers"
  ),
  SetOptHelpEntry(
    longName: "relativenumber",
    shortName: "rnu",
    description: "Show/hide relative line numbers",
  ),
  SetOptHelpEntry(
    longName: "cursorline", shortName: "cul", description: "Highlight the current line"
  ),
  SetOptHelpEntry(
    longName: "cursorcolumn",
    shortName: "cuc",
    description: "Highlight the current column",
  ),
  SetOptHelpEntry(
    longName: "statusline", shortName: "stl", description: "Show/hide status line"
  ),
  SetOptHelpEntry(
    longName: "syntax",
    shortName: "syn",
    description: "Enable/disable syntax highlighting",
  ),
  SetOptHelpEntry(
    longName: "indentationlines",
    shortName: "indl",
    description: "Enable/disable indentation guide lines",
  ),
  SetOptHelpEntry(
    longName: "autoindent", shortName: "ai", description: "Enable/disable auto indent"
  ),
  SetOptHelpEntry(
    longName: "autocloseparen",
    shortName: "acp",
    description: "Enable/disable auto close paren",
  ),
  SetOptHelpEntry(
    longName: "autodeleteparen",
    shortName: "adp",
    description: "Enable/disable auto delete paren",
  ),
  SetOptHelpEntry(
    longName: "clipboard",
    shortName: "cb",
    description: "Enable/disable system clipboard",
  ),
  SetOptHelpEntry(
    longName: "smoothscroll",
    shortName: "sms",
    description: "Enable/disable smooth scroll",
  ),
  SetOptHelpEntry(
    longName: "livereload",
    shortName: "lr",
    description: "Enable/disable live reload of config",
  ),
  SetOptHelpEntry(
    longName: "icon", shortName: "icons", description: "Show/hide icons in filer mode"
  ),
  SetOptHelpEntry(
    longName: "highlightcurrentline",
    shortName: "hcl",
    description: "Highlight the current line",
  ),
  SetOptHelpEntry(
    longName: "highlightcurrentword",
    shortName: "hcw",
    description: "Highlight other uses of the current word",
  ),
  SetOptHelpEntry(
    longName: "highlightfullspace",
    shortName: "hfs",
    description: "Highlight full width space",
  ),
  SetOptHelpEntry(
    longName: "highlightparen", shortName: "hp", description: "Highlight matching paren"
  ),
  SetOptHelpEntry(
    longName: "highlightfindchar",
    shortName: "hfc",
    description: "Highlight f/F/t/T matches",
  ),
  SetOptHelpEntry(
    longName: "highlightcolorcode",
    shortName: "hcc",
    description: "Highlight inline color codes",
  ),
  SetOptHelpEntry(
    longName: "highlightgitconflict",
    shortName: "hgc",
    description: "Highlight git merge conflict blocks",
  ),
  SetOptHelpEntry(
    longName: "highlightgitconflicttwocolor",
    shortName: "hgctc",
    description: "Use two-color (ours/theirs) conflict scheme",
  ),
  SetOptHelpEntry(
    longName: "multistatusline",
    shortName: "msl",
    description: "Enable/disable multiple status line",
  ),
  SetOptHelpEntry(
    longName: "ignorecase", shortName: "ic", description: "Enable/disable ignorecase"
  ),
  SetOptHelpEntry(
    longName: "smartcase", shortName: "scs", description: "Enable/disable smartcase"
  ),
  SetOptHelpEntry(
    longName: "incsearch",
    shortName: "is",
    description: "Enable/disable incremental search",
  ),
  SetOptHelpEntry(
    longName: "hlsearch",
    shortName: "hls",
    description: "Enable/disable search highlighting",
  ),
  SetOptHelpEntry(
    longName: "buildonsave",
    shortName: "bos",
    description: "Enable/disable build on save",
  ),
  SetOptHelpEntry(
    longName: "showgitinactive",
    shortName: "sgi",
    description: "Show/hide git branch in inactive window",
  ),
  SetOptHelpEntry(
    longName: "wrap", shortName: "", description: "Enable/disable line wrap"
  ),
  SetOptHelpEntry(
    longName: "expandtab",
    shortName: "et",
    description: "Enable/disable expand tab to spaces",
  ),
  SetOptHelpEntry(
    longName: "scrollbar", shortName: "", description: "Enable/disable scrollbar"
  ),
]

const ValueSetOptions*: seq[ValueSetOptHelpEntry] = @[
  ValueSetOptHelpEntry(
    longName: "scrollbarwidth",
    shortName: "",
    description: "Change scrollbar width",
    example: "set scrollbarwidth=2",
  ),
  ValueSetOptHelpEntry(
    longName: "tabstop",
    shortName: "ts",
    description: "Change tab stop width",
    example: "set tabstop=2",
  ),
  ValueSetOptHelpEntry(
    longName: "shiftwidth",
    shortName: "sw",
    description: "Change indent width",
    example: "set shiftwidth=2",
  ),
  ValueSetOptHelpEntry(
    longName: "softtabstop",
    shortName: "sts",
    description: "Change soft tab stop width",
    example: "set softtabstop=4",
  ),
  ValueSetOptHelpEntry(
    longName: "scrollfriction",
    shortName: "sfr",
    description: "Change smooth scroll friction",
    example: "set scrollfriction=80.0",
  ),
  ValueSetOptHelpEntry(
    longName: "scrollairdrag",
    shortName: "sad",
    description: "Change smooth scroll air drag",
    example: "set scrollairdrag=2.0",
  ),
]

proc boolSetHead(e: SetOptHelpEntry): string =
  result = "set " & e.longName & " / set no" & e.longName
  if e.shortName.len > 0:
    result.add " (" & e.shortName & "/no" & e.shortName & ")"

proc valueSetHead(e: ValueSetOptHelpEntry): string =
  result = "set " & e.longName & "=number"
  if e.shortName.len > 0:
    result.add " (" & e.shortName & ")"

proc renderGroup(g: ExCmdHelpGroup): string =
  ## Render one blank-line-separated group with per-group left-column alignment.
  var width = 0
  for e in g.entries:
    if e.syntax.len > width:
      width = e.syntax.len
  for e in g.entries:
    result.add e.syntax.alignLeft(width)
    result.add " - "
    result.add e.description
    result.add '\n'

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
  ## `set X=number (sx) - desc; e.g. set X=N` value options.
  var width = 0
  for e in BoolSetOptions:
    let h = boolSetHead(e)
    if h.len > width:
      width = h.len
  for e in BoolSetOptions:
    result.add boolSetHead(e).alignLeft(width)
    result.add " - "
    result.add e.description
    result.add '\n'

  var vwidth = 0
  for e in ValueSetOptions:
    let h = valueSetHead(e)
    if h.len > vwidth:
      vwidth = h.len
  for e in ValueSetOptions:
    result.add valueSetHead(e).alignLeft(vwidth)
    result.add " - "
    result.add e.description
    result.add "; e.g. "
    result.add e.example
    result.add '\n'
