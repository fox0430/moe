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

## Canonical metadata for every `:xxx` command-line command.
##
## `CommandLineCommandTable` is the single source of truth consumed by:
## - `command_config.nim:loadDefaultConfig` for parser alias registration
## - `command_config.nim:CommandNameTable` for TOML config canonical-name resolution
## - `command_completion.nim:CommandDescriptions` for the completion popup
## - `help_generator.nim:renderExitingSection` /
##   `renderCommandLineHead` / `renderCommandLineTail` for help text rendering
##
## Adding a new command alias means appending one entry here. No other
## file needs to be updated unless a new `CommandLineAction` enum value is
## also introduced (which still lives in `command_line/types.nim`).

import std/[options, tables]

import command_line/types, help_description

descriptionFromStringConverter()

type
  HelpEntry* = object ## A single line in the help text.
    syntax*: string
      ## Left of the dash, e.g. `":w"`, `"e filename"`, `"%s/keyword1/keyword2/"`.
    description*: Description
      ## Right of the dash. A `string → Description` converter in
      ## `help_description.nim` parses markdown backticks into code
      ## segments at construction time, so plain-string literals here
      ## still compile.

  CommandLineCommandSpec* = object
    name*: string
      ## Lookup key. Short alias (`q`) and long alias (`quit`) live as
      ## separate specs since they have different roles.
    completionDescription*: string
      ## Shown in the completion popup. Empty string means "not in completion".
    helpEntries*: seq[HelpEntry]
      ## Lines emitted in help text. Empty = no help line. Multi-usage
      ## families (e.g. `:e`) have multiple entries.
    action*: Option[CommandLineAction]
      ## Parser dispatch target. `none` for help-only display variants
      ## (`q!`, `wqa!` etc. — the parser treats `!` as a flag on the bare
      ## command).
    isCanonicalLong*: bool
      ## When `true`, this spec's `name` is the canonical long form used
      ## in TOML `[CommandAliases]` config and exposed via `CommandNameTable`.
      ## Exactly one spec per action should set this to `true`.
    takesFilePath*: bool
      ## When `true`, completion offers file paths when the user types
      ## `:<name> <prefix>`. Derived as
      ## `command_completion.FilePathCommands`.
    keymapBaseDescription*: string
      ## When non-empty, this spec is a `:<name>` keymap RHS target. The
      ## description shown to users is built as
      ## `keymapBaseDescription & " (:" & name & ")"`. Derived as
      ## `command_config.keyMappableCommandModeAliases`.

const CommandLineCommandTable*: seq[CommandLineCommandSpec] = @[
  # Quit / save (Exiting section)
  CommandLineCommandSpec(
    name: "q",
    completionDescription: "Quit",
    helpEntries: @[HelpEntry(syntax: ":q", description: "Quit")],
    action: some(claQuit),
    isCanonicalLong: false,
    keymapBaseDescription: "Quit",
  ),
  CommandLineCommandSpec(
    name: "quit",
    completionDescription: "",
    helpEntries: @[],
    action: some(claQuit),
    isCanonicalLong: true,
    keymapBaseDescription: "Quit",
  ),
  CommandLineCommandSpec(
    name: "q!",
    completionDescription: "",
    helpEntries: @[HelpEntry(syntax: ":q!", description: "Force quit")],
    action: none(CommandLineAction),
    isCanonicalLong: false,
  ),
  CommandLineCommandSpec(
    name: "qa",
    completionDescription: "Quit all windows",
    helpEntries: @[HelpEntry(syntax: ":qa", description: "Quit all windows")],
    action: some(claQuitAll),
    isCanonicalLong: false,
    keymapBaseDescription: "Quit all",
  ),
  CommandLineCommandSpec(
    name: "quitall",
    completionDescription: "",
    helpEntries: @[],
    action: some(claQuitAll),
    isCanonicalLong: true,
    keymapBaseDescription: "Quit all",
  ),
  CommandLineCommandSpec(
    name: "qa!",
    completionDescription: "",
    helpEntries: @[HelpEntry(syntax: ":qa!", description: "Force quit all windows")],
    action: none(CommandLineAction),
    isCanonicalLong: false,
  ),
  CommandLineCommandSpec(
    name: "cq",
    completionDescription: "Quit with non-zero exit code",
    helpEntries:
      @[HelpEntry(syntax: ":cq", description: "Quit with non-zero exit code")],
    action: some(claCquit),
    isCanonicalLong: false,
  ),
  CommandLineCommandSpec(
    name: "cquit",
    completionDescription: "",
    helpEntries: @[],
    action: some(claCquit),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "w",
    completionDescription: "Write file",
    helpEntries: @[HelpEntry(syntax: ":w", description: "Write file")],
    action: some(claSave),
    isCanonicalLong: false,
    takesFilePath: true,
    keymapBaseDescription: "Save current buffer",
  ),
  CommandLineCommandSpec(
    name: "save",
    completionDescription: "",
    helpEntries: @[],
    action: some(claSave),
    isCanonicalLong: true,
    keymapBaseDescription: "Save current buffer",
  ),
  CommandLineCommandSpec(
    name: "w!",
    completionDescription: "",
    helpEntries: @[HelpEntry(syntax: ":w!", description: "Force write")],
    action: none(CommandLineAction),
    isCanonicalLong: false,
  ),
  CommandLineCommandSpec(
    name: "wa",
    completionDescription: "Write all files",
    helpEntries: @[],
    action: some(claSaveAll),
    isCanonicalLong: false,
    keymapBaseDescription: "Save all buffers",
  ),
  CommandLineCommandSpec(
    name: "saveall",
    completionDescription: "",
    helpEntries: @[],
    action: some(claSaveAll),
    isCanonicalLong: true,
    keymapBaseDescription: "Save all buffers",
  ),
  CommandLineCommandSpec(
    name: "write",
    completionDescription: "",
    helpEntries: @[],
    action: some(claSave),
    isCanonicalLong: false,
    takesFilePath: true,
  ),
  CommandLineCommandSpec(
    name: "wq",
    completionDescription: "Write and quit",
    helpEntries: @[HelpEntry(syntax: ":wq", description: "Write and quit")],
    action: some(claSaveAndQuit),
    isCanonicalLong: false,
    keymapBaseDescription: "Save and quit",
  ),
  CommandLineCommandSpec(
    name: "saveandquit",
    completionDescription: "",
    helpEntries: @[],
    action: some(claSaveAndQuit),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "wq!",
    completionDescription: "",
    helpEntries:
      @[HelpEntry(syntax: ":wq!", description: "Force write and quit window")],
    action: none(CommandLineAction),
    isCanonicalLong: false,
  ),
  CommandLineCommandSpec(
    name: "x",
    completionDescription: "Write if modified and quit",
    helpEntries:
      @[HelpEntry(syntax: ":x or :xit", description: "Write if modified and quit")],
    action: some(claSaveIfModifiedAndQuit),
    isCanonicalLong: false,
    keymapBaseDescription: "Save if modified and quit",
  ),
  CommandLineCommandSpec(
    name: "xit",
    completionDescription: "Write if modified and quit",
    helpEntries: @[],
    action: some(claSaveIfModifiedAndQuit),
    isCanonicalLong: true,
    keymapBaseDescription: "Save if modified and quit",
  ),
  CommandLineCommandSpec(
    name: "x!",
    completionDescription: "",
    helpEntries:
      @[HelpEntry(syntax: ":x!", description: "Force write if modified and quit")],
    action: none(CommandLineAction),
    isCanonicalLong: false,
  ),
  CommandLineCommandSpec(
    name: "wqa",
    completionDescription: "Write and quit all windows",
    helpEntries: @[HelpEntry(syntax: ":wqa", description: "Write and quit all windows")],
    action: some(claSaveAllAndQuit),
    isCanonicalLong: false,
    keymapBaseDescription: "Save all and quit",
  ),
  CommandLineCommandSpec(
    name: "saveallandquit",
    completionDescription: "",
    helpEntries: @[],
    action: some(claSaveAllAndQuit),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "wqa!",
    completionDescription: "",
    helpEntries:
      @[HelpEntry(syntax: ":wqa!", description: "Force write and quit all windows")],
    action: none(CommandLineAction),
    isCanonicalLong: false,
  ),
  # Edit / open file (multi-usage `:e`)
  CommandLineCommandSpec(
    name: "e",
    completionDescription: "Open file",
    helpEntries: @[
      HelpEntry(syntax: "e filename", description: "Open file"),
      HelpEntry(
        syntax: "e", description: "Reload current file (error if unsaved changes)"
      ),
      HelpEntry(
        syntax: "e!", description: "Force reload current file (discard unsaved changes)"
      ),
      HelpEntry(
        syntax: "e! filename", description: "Open file (discard unsaved changes)"
      ),
    ],
    action: some(claEdit),
    isCanonicalLong: false,
    takesFilePath: true,
  ),
  CommandLineCommandSpec(
    name: "edit",
    completionDescription: "",
    helpEntries: @[],
    action: some(claEdit),
    isCanonicalLong: true,
    takesFilePath: true,
  ),
  CommandLineCommandSpec(
    name: "ene",
    completionDescription: "Create a new empty buffer",
    helpEntries: @[HelpEntry(syntax: "ene", description: "Create a new empty buffer")],
    action: some(claEnew),
    isCanonicalLong: false,
  ),
  CommandLineCommandSpec(
    name: "enew",
    completionDescription: "",
    helpEntries: @[],
    action: some(claEnew),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "new",
    completionDescription: "Create a new empty buffer in a horizontally split window",
    helpEntries: @[
      HelpEntry(
        syntax: "new",
        description: "Create a new empty buffer in a horizontally split window",
      )
    ],
    action: some(claNew),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "vnew",
    completionDescription: "Create a new empty buffer in a vertically split window",
    helpEntries: @[
      HelpEntry(
        syntax: "vnew",
        description: "Create a new empty buffer in a vertically split window",
      )
    ],
    action: some(claVnew),
    isCanonicalLong: true,
  ),
  # Edit history
  CommandLineCommandSpec(
    name: "u",
    completionDescription: "Undo the last change",
    helpEntries: @[],
    action: some(claUndo),
    isCanonicalLong: false,
  ),
  CommandLineCommandSpec(
    name: "undo",
    completionDescription: "Undo the last change",
    helpEntries: @[HelpEntry(syntax: "undo", description: "Undo the last change")],
    action: some(claUndo),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "redo",
    completionDescription: "Redo the last undone change",
    helpEntries:
      @[HelpEntry(syntax: "redo", description: "Redo the last undone change")],
    action: some(claRedo),
    isCanonicalLong: true,
  ),
  # Substitute / delete lines
  CommandLineCommandSpec(
    name: "s",
    completionDescription: "Substitute",
    helpEntries: @[],
    action: some(claSubstitute),
    isCanonicalLong: false,
  ),
  CommandLineCommandSpec(
    name: "substitute",
    completionDescription: "",
    helpEntries: @[],
    action: some(claSubstitute),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "delete",
    completionDescription: "Delete current line and copy to register",
    helpEntries: @[
      HelpEntry(
        syntax: "delete", description: "Delete current line and copy to register"
      )
    ],
    action: some(claDeleteLines),
    isCanonicalLong: true,
  ),
  # Window split (multi-usage `:vs` / `:sp`)
  CommandLineCommandSpec(
    name: "vs",
    completionDescription: "Vertical split window",
    helpEntries: @[
      HelpEntry(syntax: "vs", description: "Vertical split window"),
      HelpEntry(syntax: "vs filename", description: "Open in a vertical split window"),
    ],
    action: some(claVSplit),
    isCanonicalLong: false,
    takesFilePath: true,
  ),
  CommandLineCommandSpec(
    name: "vsplit",
    completionDescription: "",
    helpEntries: @[],
    action: some(claVSplit),
    isCanonicalLong: true,
    takesFilePath: true,
  ),
  CommandLineCommandSpec(
    name: "sp",
    completionDescription: "Horizontal split window",
    helpEntries: @[
      HelpEntry(syntax: "sp", description: "Horizontal split window"),
      HelpEntry(syntax: "sp filename", description: "Open in a horizontal split window"),
    ],
    action: some(claHSplit),
    isCanonicalLong: false,
    takesFilePath: true,
  ),
  CommandLineCommandSpec(
    name: "hsplit",
    completionDescription: "",
    helpEntries: @[],
    action: some(claHSplit),
    isCanonicalLong: true,
    takesFilePath: true,
  ),
  CommandLineCommandSpec(
    name: "split",
    completionDescription: "",
    helpEntries: @[],
    action: some(claHSplit),
    isCanonicalLong: false,
    takesFilePath: true,
  ),
  CommandLineCommandSpec(
    name: "only",
    completionDescription: "Close all other windows",
    helpEntries: @[HelpEntry(syntax: "only", description: "Close all other windows")],
    action: some(claOnlyWindow),
    isCanonicalLong: true,
  ),
  # Buffer management
  CommandLineCommandSpec(
    name: "ls",
    completionDescription: "Display all buffers",
    helpEntries: @[HelpEntry(syntax: "ls", description: "Display all buffers")],
    action: some(claBufferManager),
    isCanonicalLong: false,
  ),
  CommandLineCommandSpec(
    name: "buffermanager",
    completionDescription: "",
    helpEntries: @[],
    action: some(claBufferManager),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "b",
    completionDescription: "Switch to buffer",
    helpEntries: @[],
    action: some(claBuffer),
    isCanonicalLong: false,
  ),
  CommandLineCommandSpec(
    name: "buffer",
    completionDescription: "Switch to buffer",
    helpEntries: @[],
    action: some(claBuffer),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "bn",
    completionDescription: "Switch to the next buffer",
    helpEntries: @[],
    action: some(claBufferNext),
    isCanonicalLong: false,
    keymapBaseDescription: "Switch to next buffer",
  ),
  CommandLineCommandSpec(
    name: "bnext",
    completionDescription: "Switch to the next buffer",
    helpEntries: @[HelpEntry(syntax: "bnext", description: "Switch to the next buffer")],
    action: some(claBufferNext),
    isCanonicalLong: false,
    keymapBaseDescription: "Switch to next buffer",
  ),
  CommandLineCommandSpec(
    name: "buffernext",
    completionDescription: "",
    helpEntries: @[],
    action: some(claBufferNext),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "bp",
    completionDescription: "Switch to the previous buffer",
    helpEntries: @[],
    action: some(claBufferPrev),
    isCanonicalLong: false,
    keymapBaseDescription: "Switch to previous buffer",
  ),
  CommandLineCommandSpec(
    name: "bprev",
    completionDescription: "Switch to the previous buffer",
    helpEntries:
      @[HelpEntry(syntax: "bprev", description: "Switch to the previous buffer")],
    action: some(claBufferPrev),
    isCanonicalLong: false,
    keymapBaseDescription: "Switch to previous buffer",
  ),
  CommandLineCommandSpec(
    name: "bprevious",
    completionDescription: "Switch to the previous buffer",
    helpEntries: @[],
    action: some(claBufferPrev),
    isCanonicalLong: false,
    keymapBaseDescription: "Switch to previous buffer",
  ),
  CommandLineCommandSpec(
    name: "bufferprev",
    completionDescription: "",
    helpEntries: @[],
    action: some(claBufferPrev),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "bf",
    completionDescription: "Switch to the first buffer",
    helpEntries: @[],
    action: some(claBufferFirst),
    isCanonicalLong: false,
    keymapBaseDescription: "Switch to first buffer",
  ),
  CommandLineCommandSpec(
    name: "bfirst",
    completionDescription: "Switch to the first buffer",
    helpEntries:
      @[HelpEntry(syntax: "bfirst", description: "Switch to the first buffer")],
    action: some(claBufferFirst),
    isCanonicalLong: false,
    keymapBaseDescription: "Switch to first buffer",
  ),
  CommandLineCommandSpec(
    name: "brewind",
    completionDescription: "Switch to the first buffer",
    helpEntries: @[],
    action: some(claBufferFirst),
    isCanonicalLong: false,
  ),
  CommandLineCommandSpec(
    name: "bufferfirst",
    completionDescription: "",
    helpEntries: @[],
    action: some(claBufferFirst),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "bl",
    completionDescription: "Switch to the last buffer",
    helpEntries: @[],
    action: some(claBufferLast),
    isCanonicalLong: false,
    keymapBaseDescription: "Switch to last buffer",
  ),
  CommandLineCommandSpec(
    name: "blast",
    completionDescription: "Switch to the last buffer",
    helpEntries: @[HelpEntry(syntax: "blast", description: "Switch to the last buffer")],
    action: some(claBufferLast),
    isCanonicalLong: false,
    keymapBaseDescription: "Switch to last buffer",
  ),
  CommandLineCommandSpec(
    name: "bufferlast",
    completionDescription: "",
    helpEntries: @[],
    action: some(claBufferLast),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "bd",
    completionDescription: "Delete buffer",
    helpEntries: @[HelpEntry(syntax: "bd or bd number", description: "Delete buffer")],
    action: some(claBufferDelete),
    isCanonicalLong: false,
    keymapBaseDescription: "Delete current buffer",
  ),
  CommandLineCommandSpec(
    name: "bdelete",
    completionDescription: "Delete buffer",
    helpEntries: @[],
    action: some(claBufferDelete),
    isCanonicalLong: false,
    keymapBaseDescription: "Delete current buffer",
  ),
  CommandLineCommandSpec(
    name: "bufferdelete",
    completionDescription: "",
    helpEntries: @[],
    action: some(claBufferDelete),
    isCanonicalLong: true,
  ),
  # File tree sidebar (multi-usage)
  CommandLineCommandSpec(
    name: "filetree",
    completionDescription: "Toggle FileTree sidebar",
    helpEntries: @[
      HelpEntry(syntax: "filetree", description: "Toggle FileTree sidebar"),
      HelpEntry(
        syntax: "filetree path",
        description: "Toggle FileTree sidebar with specified root path",
      ),
    ],
    action: some(claFileTree),
    isCanonicalLong: true,
    takesFilePath: true,
  ),
  # Theme / search / whitespace
  CommandLineCommandSpec(
    name: "theme",
    completionDescription: "Change color theme; e.g. theme dark",
    helpEntries: @[
      HelpEntry(
        syntax: "theme themeName", description: "Change color theme; e.g. `theme dark`"
      )
    ],
    action: some(claTheme),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "noh",
    completionDescription: "Turn off search highlights",
    helpEntries: @[HelpEntry(syntax: "noh", description: "Turn off search highlights")],
    action: some(claClearSearchHighlight),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "stripwhitespace",
    completionDescription: "Delete trailing spaces",
    helpEntries:
      @[HelpEntry(syntax: "stripwhitespace", description: "Delete trailing spaces")],
    action: some(claStripWhitespace),
    isCanonicalLong: true,
  ),
  # Set (no help entry — handled separately)
  CommandLineCommandSpec(
    name: "set",
    completionDescription: "Set option",
    helpEntries: @[],
    action: some(claSet),
    isCanonicalLong: true,
  ),
  # Build / LSP / log
  CommandLineCommandSpec(
    name: "build",
    completionDescription: "Build the current buffer",
    helpEntries: @[HelpEntry(syntax: "build", description: "Build the current buffer")],
    action: some(claBuild),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "lspfold",
    completionDescription: "LSP Folding Range",
    helpEntries: @[HelpEntry(syntax: "lspfold", description: "LSP Folding Range")],
    action: some(claLspFold),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "lspformat",
    completionDescription: "LSP Document Formatting",
    helpEntries:
      @[HelpEntry(syntax: "lspformat", description: "LSP Document Formatting")],
    action: some(claLspFormat),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "log",
    completionDescription: "Open a log viewer for editor log",
    helpEntries:
      @[HelpEntry(syntax: "log", description: "Open a log viewer for editor log")],
    action: some(claLogViewer),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "messages",
    completionDescription: "Open a log viewer for editor log",
    helpEntries: @[],
    action: some(claLogViewer),
    isCanonicalLong: false,
  ),
  CommandLineCommandSpec(
    name: "lsplog",
    completionDescription: "Open a log viewer for LSP log",
    helpEntries:
      @[HelpEntry(syntax: "lsplog", description: "Open a log viewer for LSP log")],
    action: some(claLspLog),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "lsprestart",
    completionDescription: "Restart the current LSP server",
    helpEntries:
      @[HelpEntry(syntax: "lsprestart", description: "Restart the current LSP server")],
    action: some(claLspRestart),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "lspcallhierarchyincoming",
    completionDescription: "Show incoming calls (callers) at cursor",
    helpEntries: @[
      HelpEntry(
        syntax: "lspcallhierarchyincoming",
        description: "Show incoming calls (callers) at cursor",
      )
    ],
    action: some(claLspCallHierarchyIncoming),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "lspcallhierarchyoutgoing",
    completionDescription: "Show outgoing calls (callees) at cursor",
    helpEntries: @[
      HelpEntry(
        syntax: "lspcallhierarchyoutgoing",
        description: "Show outgoing calls (callees) at cursor",
      )
    ],
    action: some(claLspCallHierarchyOutgoing),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "lspexecommand",
    completionDescription: "Execute LSP command",
    helpEntries: @[],
    action: some(claLspExecuteCommand),
    isCanonicalLong: true,
  ),
  # Misc single-entry
  CommandLineCommandSpec(
    name: "help",
    completionDescription: "Open this help",
    helpEntries: @[HelpEntry(syntax: "help", description: "Open this help")],
    action: some(claHelp),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "putconfigfile",
    completionDescription: "Put a sample configuration file in ~/.config/moe",
    helpEntries: @[
      HelpEntry(
        syntax: "putconfigfile",
        description: "Put a sample configuration file in ~/.config/moe",
      )
    ],
    action: some(claPutConfigFile),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "moerc",
    completionDescription: "Open the configuration file (moerc.toml) for editing",
    helpEntries: @[
      HelpEntry(
        syntax: "moerc",
        description: "Open the configuration file (moerc.toml) for editing",
      )
    ],
    action: some(claEditConfigFile),
    isCanonicalLong: false,
  ),
  CommandLineCommandSpec(
    name: "editconfigfile",
    completionDescription: "",
    helpEntries: @[],
    action: some(claEditConfigFile),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "quickrun",
    completionDescription: "Quick run",
    helpEntries: @[HelpEntry(syntax: "quickrun", description: "Quick run")],
    action: some(claQuickRun),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "recent",
    completionDescription: "Open recent file selection mode (Only supported on Linux)",
    helpEntries: @[
      HelpEntry(
        syntax: "recent",
        description: "Open recent file selection mode (Only supported on Linux)",
      )
    ],
    action: some(claRecentFile),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "backup",
    completionDescription: "Open backup file manager",
    helpEntries: @[HelpEntry(syntax: "backup", description: "Open backup file manager")],
    action: some(claBackupManager),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "config",
    completionDescription: "Open configuration mode",
    helpEntries: @[HelpEntry(syntax: "config", description: "Open configuration mode")],
    action: some(claConfig),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "debug",
    completionDescription: "Open debug mode",
    helpEntries: @[HelpEntry(syntax: "debug", description: "Open debug mode")],
    action: some(claDebug),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "jump",
    completionDescription: "Open Jump list viewer",
    helpEntries: @[HelpEntry(syntax: "jump", description: "Open Jump list viewer")],
    action: some(claJumpList),
    isCanonicalLong: false,
  ),
  CommandLineCommandSpec(
    name: "jumplist",
    completionDescription: "",
    helpEntries: @[],
    action: some(claJumpList),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "changes",
    completionDescription: "Show Change list",
    helpEntries: @[HelpEntry(syntax: "changes", description: "Show Change list")],
    action: some(claChanges),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "bookmarks",
    completionDescription: "Show bookmark list",
    helpEntries: @[HelpEntry(syntax: "bookmarks", description: "Show bookmark list")],
    action: some(claBookmarks),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "conflictnext",
    completionDescription: "Jump to next git merge conflict block",
    helpEntries: @[
      HelpEntry(
        syntax: "conflictnext", description: "Jump to next git merge conflict block"
      )
    ],
    action: some(claConflictNext),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "conflictprev",
    completionDescription: "Jump to previous git merge conflict block",
    helpEntries: @[
      HelpEntry(
        syntax: "conflictprev", description: "Jump to previous git merge conflict block"
      )
    ],
    action: some(claConflictPrev),
    isCanonicalLong: true,
  ),
  # Terminal / background / man
  CommandLineCommandSpec(
    name: "terminal",
    completionDescription: "Open terminal emulator (default shell)",
    helpEntries: @[
      HelpEntry(
        syntax: "terminal", description: "Open terminal emulator (default shell)"
      ),
      HelpEntry(
        syntax: "terminal command", description: "Run command in terminal emulator"
      ),
    ],
    action: some(claTerminal),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "bg",
    completionDescription: "Pause the editor and show the recent terminal output",
    helpEntries: @[
      HelpEntry(
        syntax: "bg",
        description: "Pause the editor and show the recent terminal output",
      )
    ],
    action: some(claBackground),
    isCanonicalLong: false,
  ),
  CommandLineCommandSpec(
    name: "background",
    completionDescription: "",
    helpEntries: @[],
    action: some(claBackground),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "man",
    completionDescription:
      "Show the given UNIX manual page, if available; e.g. :man man",
    helpEntries: @[
      HelpEntry(
        syntax: "man arguments",
        description: "Show the given UNIX manual page, if available; e.g. `:man man`",
      )
    ],
    action: some(claMan),
    isCanonicalLong: true,
  ),
  # Filer (TOML-only canonical name)
  CommandLineCommandSpec(
    name: "filer",
    completionDescription: "",
    helpEntries: @[],
    action: some(claFiler),
    isCanonicalLong: true,
  ),
  # Shell (TOML-only canonical name; help is in CommandLineSpecialHelp)
  CommandLineCommandSpec(
    name: "shell",
    completionDescription: "",
    helpEntries: @[],
    action: some(claShellCommand),
    isCanonicalLong: true,
  ),
  # Runtime key mapping (the `noremap` aliases are documented under their
  # canonical-long counterpart; their `helpEntries` stay empty so the help
  # text doesn't list the same binding twice).
  CommandLineCommandSpec(
    name: "map",
    completionDescription: "Map keys (all modes)",
    helpEntries: @[
      HelpEntry(syntax: "map {lhs} {rhs}", description: "Map keys (all modes)"),
      HelpEntry(syntax: "map", description: "List all mode mappings"),
    ],
    action: some(claMap),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "noremap",
    completionDescription: "Map keys non-recursively (all modes)",
    helpEntries: @[],
    action: some(claNoremap),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "nmap",
    completionDescription: "Map keys (Normal mode)",
    helpEntries: @[
      HelpEntry(syntax: "nmap {lhs} {rhs}", description: "Map keys (Normal mode)"),
      HelpEntry(syntax: "nmap", description: "List all Normal mode mappings"),
    ],
    action: some(claNmap),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "nnoremap",
    completionDescription: "Map keys non-recursively (Normal mode)",
    helpEntries: @[],
    action: some(claNnoremap),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "imap",
    completionDescription: "Map keys (Insert mode)",
    helpEntries: @[
      HelpEntry(syntax: "imap {lhs} {rhs}", description: "Map keys (Insert mode)"),
      HelpEntry(syntax: "imap", description: "List all Insert mode mappings"),
    ],
    action: some(claImap),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "inoremap",
    completionDescription: "Map keys non-recursively (Insert mode)",
    helpEntries: @[],
    action: some(claInoremap),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "vmap",
    completionDescription: "Map keys (Visual modes)",
    helpEntries: @[
      HelpEntry(syntax: "vmap {lhs} {rhs}", description: "Map keys (Visual modes)"),
      HelpEntry(syntax: "vmap", description: "List all Visual mode mappings"),
    ],
    action: some(claVmap),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "vnoremap",
    completionDescription: "Map keys non-recursively (Visual modes)",
    helpEntries: @[],
    action: some(claVnoremap),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "rmap",
    completionDescription: "Map keys (Replace mode)",
    helpEntries: @[
      HelpEntry(syntax: "rmap {lhs} {rhs}", description: "Map keys (Replace mode)"),
      HelpEntry(syntax: "rmap", description: "List all Replace mode mappings"),
    ],
    action: some(claRmap),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "cmap",
    completionDescription: "Map keys (Command mode)",
    helpEntries: @[
      HelpEntry(syntax: "cmap {lhs} {rhs}", description: "Map keys (Command mode)"),
      HelpEntry(syntax: "cmap", description: "List all Command mode mappings"),
    ],
    action: some(claCmap),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "cnoremap",
    completionDescription: "Map keys non-recursively (Command mode)",
    helpEntries: @[],
    action: some(claCnoremap),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "unmap",
    completionDescription: "Unmap keys (all modes)",
    helpEntries:
      @[HelpEntry(syntax: "unmap {lhs}", description: "Unmap keys (all modes)")],
    action: some(claUnmap),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "nunmap",
    completionDescription: "Unmap keys (Normal mode)",
    helpEntries:
      @[HelpEntry(syntax: "nunmap {lhs}", description: "Unmap keys (Normal mode)")],
    action: some(claNunmap),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "iunmap",
    completionDescription: "Unmap keys (Insert mode)",
    helpEntries:
      @[HelpEntry(syntax: "iunmap {lhs}", description: "Unmap keys (Insert mode)")],
    action: some(claIunmap),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "vunmap",
    completionDescription: "Unmap keys (Visual modes)",
    helpEntries:
      @[HelpEntry(syntax: "vunmap {lhs}", description: "Unmap keys (Visual modes)")],
    action: some(claVunmap),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "runmap",
    completionDescription: "Unmap keys (Replace mode)",
    helpEntries:
      @[HelpEntry(syntax: "runmap {lhs}", description: "Unmap keys (Replace mode)")],
    action: some(claRunmap),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "cunmap",
    completionDescription: "Unmap keys (Command mode)",
    helpEntries:
      @[HelpEntry(syntax: "cunmap {lhs}", description: "Unmap keys (Command mode)")],
    action: some(claCunmap),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "mapclear",
    completionDescription: "Clear mappings (all modes)",
    helpEntries:
      @[HelpEntry(syntax: "mapclear", description: "Clear mappings (all modes)")],
    action: some(claMapclear),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "nmapclear",
    completionDescription: "Clear mappings (Normal mode)",
    helpEntries:
      @[HelpEntry(syntax: "nmapclear", description: "Clear mappings (Normal mode)")],
    action: some(claNmapclear),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "imapclear",
    completionDescription: "Clear mappings (Insert mode)",
    helpEntries:
      @[HelpEntry(syntax: "imapclear", description: "Clear mappings (Insert mode)")],
    action: some(claImapclear),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "vmapclear",
    completionDescription: "Clear mappings (Visual modes)",
    helpEntries:
      @[HelpEntry(syntax: "vmapclear", description: "Clear mappings (Visual modes)")],
    action: some(claVmapclear),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "rmapclear",
    completionDescription: "Clear mappings (Replace mode)",
    helpEntries:
      @[HelpEntry(syntax: "rmapclear", description: "Clear mappings (Replace mode)")],
    action: some(claRmapclear),
    isCanonicalLong: true,
  ),
  CommandLineCommandSpec(
    name: "cmapclear",
    completionDescription: "Clear mappings (Command mode)",
    helpEntries:
      @[HelpEntry(syntax: "cmapclear", description: "Clear mappings (Command mode)")],
    action: some(claCmapclear),
    isCanonicalLong: true,
  ),
]

const CommandLineSpecialHelp*:
  tuple[
    lineNumber: HelpEntry,
    shellCommand: HelpEntry,
    substitute: HelpEntry,
    deleteAll: HelpEntry,
    deleteRange: HelpEntry,
  ] = (
  ## Help-only entries with no alias. The parser handles these as
  ## special syntax (line number jump, `!` shell escape, `%s/.../.../`
  ## substitute, `%d` / `N,Md` range delete). Named-field tuple so
  ## `help_generator.nim` references them by name rather than by index.
  lineNumber:
    HelpEntry(syntax: "number", description: "Jump to line number; e.g. `:10`"),
  shellCommand:
    HelpEntry(syntax: "! shell command", description: "Shell command execution"),
  substitute: HelpEntry(
    syntax: "%s/keyword1/keyword2/", description: "Replace text (normal mode only)"
  ),
  deleteAll:
    HelpEntry(syntax: "%d", description: "Delete all lines and copy to register"),
  deleteRange: HelpEntry(
    syntax: "1,10d", description: "Delete lines in range and copy to register"
  ),
)

const CommandLineCommandIndex: Table[string, int] = block:
  ## Compile-time `name -> table index` lookup used by `findCommandLineCommand`
  ## so help rendering and any other lookup is O(1) rather than O(N).
  var t: Table[string, int]
  for i, spec in CommandLineCommandTable:
    t[spec.name] = i
  t

proc findCommandLineCommand*(name: string): Option[CommandLineCommandSpec] =
  ## O(1) lookup by name. Used by help rendering to look up specs from
  ## name lists.
  if name in CommandLineCommandIndex:
    return some(CommandLineCommandTable[CommandLineCommandIndex[name]])
  none(CommandLineCommandSpec)
