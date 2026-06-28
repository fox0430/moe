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

## Command-line types, action enum, result variant, and the
## ArgumentRequiredActions set (plus isNoArgumentAction).

import std/[tables, options]

import pkg/results

type
  CommandLineAction* = enum
    claQuit # :q
    claQuitAll # :qa (quit all)
    claSave # :w
    claSaveAll # :wa (write all)
    claSaveAndQuit # :wq, :x
    claSaveAllAndQuit # :wqa, :xa (save all and quit)
    claEdit # :e
    claEnew # :ene, :enew (new empty buffer)
    claSet # :set
    claHelp # :help, :h
    claSubstitute # :s
    claDeleteLines # :d, :%d (delete lines)
    claGoto # :123 (go to line 123)
    claVSplit # :vs (vertical split)
    claHSplit # :sp (horizontal split)
    claNew # :new (new empty buffer in horizontal split)
    claVnew # :vnew (new empty buffer in vertical split)
    claBufferNext # :bnext, :bn (next buffer)
    claBufferPrev # :bprev, :bp (previous buffer)
    claBufferFirst # :bfirst, :bf (first buffer)
    claBufferLast # :blast, :bl (last buffer)
    claBufferDelete # :bd, :bdelete (delete buffer)
    claBuffer # :b (switch to buffer by number or name)
    claStripWhitespace # :stripwhitespace, :stripws (remove trailing whitespace)
    claFiler # :filer (open file explorer)
    claLogViewer # :log (open log viewer)
    claQuickRun # :run (quick run)
    claBufferManager # :buffers, :ls (open buffer manager)
    claBackupManager # :backup (open backup manager)
    claRecentFile # :recent (open recent file selection mode)
    claClearSearchHighlight # :nohlsearch (clear search highlighting)
    claShellCommand # :! (execute shell command)
    claBackground # :bg (pause editor and show terminal)
    claJumpList # :jump (show jump list)
    claChanges # :changes (show change list)
    claBookmarks # :bookmarks (show bookmark list)
    claConflictNext # :conflictnext (jump to next git conflict block)
    claConflictPrev # :conflictprev (jump to previous git conflict block)
    claBuild # :build (build current buffer)
    claDebug # :debug (open debug mode)
    claConfig # :config (open configuration mode)
    claPutConfigFile # :putconfigfile (write sample config file)
    claMan # :man (show manual page)
    claTheme # :theme (change color theme)
    claLspLog # :lsplog (open LSP log viewer)
    claLspFormat # :lspformat (LSP document formatting)
    claLspRestart # :lsprestart (restart LSP server)
    claLspFold # :lspfold (LSP folding range)
    claLspExecuteCommand # :lspexecommand (LSP execute command)
    claLspCallHierarchyIncoming # :lspcallhierarchyincoming (LSP incoming calls)
    claLspCallHierarchyOutgoing # :lspcallhierarchyoutgoing (LSP outgoing calls)
    claTerminal # :terminal (open terminal emulator)
    claMap # :map {lhs} {rhs} (all modes)
    claNmap # :nmap {lhs} {rhs} (normal mode)
    claImap # :imap {lhs} {rhs} (insert mode)
    claVmap # :vmap {lhs} {rhs} (visual modes)
    claRmap # :rmap {lhs} {rhs} (replace mode)
    claCmap # :cmap {lhs} {rhs} (command-line mode)
    claNoremap # :noremap {lhs} {rhs} (all modes, non-recursive)
    claNnoremap # :nnoremap {lhs} {rhs} (normal mode, non-recursive)
    claInoremap # :inoremap {lhs} {rhs} (insert mode, non-recursive)
    claVnoremap # :vnoremap {lhs} {rhs} (visual modes, non-recursive)
    claCnoremap # :cnoremap {lhs} {rhs} (command-line mode, non-recursive)
    claUnmap # :unmap {lhs} (all modes)
    claNunmap # :nunmap {lhs} (normal mode)
    claIunmap # :iunmap {lhs} (insert mode)
    claVunmap # :vunmap {lhs} (visual modes)
    claRunmap # :runmap {lhs} (replace mode)
    claCunmap # :cunmap {lhs} (command-line mode)
    claMapclear # :mapclear (all modes)
    claNmapclear # :nmapclear (normal mode)
    claImapclear # :imapclear (insert mode)
    claVmapclear # :vmapclear (visual modes)
    claRmapclear # :rmapclear (replace mode)
    claCmapclear # :cmapclear (command-line mode)
    claOnlyWindow # :only (close all other windows)
    claEditConfigFile # :moerc (open config file for editing)
    claFileTree # :filetree (toggle file tree sidebar)
    claCquit # :cq, :cquit (quit with non-zero exit code)
    claUnknown # Unknown command

  ParsedCommand* = object
    action*: CommandLineAction
    args*: seq[string]
    flags*: seq[string]
    rawText*: string

  ShellCommandEntry* = object
    command*: string ## The shell command to execute
    description*: string ## Optional description for completion

  CommandLineParser* = ref object
    aliases*: Table[string, CommandLineAction]
    aliasDescriptions*: Table[string, string] ## Custom descriptions for aliases
    shellCommands*: Table[string, ShellCommandEntry] ## Shell command definitions
    validators*: Table[CommandLineAction, proc(args: seq[string]): Result[void, string]]

  CommandLineResult* = object
    case kind*: CommandLineAction
    of claQuit:
      forceQuit*: bool # true for :q!
    of claQuitAll:
      forceQuitAll*: bool # true for :qa!
    of claSave:
      filename*: Option[string]
      forceSave*: bool # true for :w!
    of claSaveAll:
      forceSaveAll*: bool # true for :wa!
    of claSaveAndQuit:
      saveFilename*: Option[string]
      forceSaveAndQuit*: bool # true for :wq!
    of claSaveAllAndQuit:
      forceSaveAllAndQuit*: bool # true for :wqa!
    of claEdit:
      editFilename*: Option[string]
      forceEdit*: bool # true for :e!
    of claEnew:
      discard
    of claGoto:
      lineNumber*: int
    of claSet:
      option*: string
      value*: Option[string]
    of claSubstitute:
      pattern*: string
      replacement*: string
      substituteFlags*: string
      hasRange*: bool # Whether a line range is specified
      isGlobal*: bool # Whether % prefix (all lines)
      startLine*: int # Start line (1-based, 0 means current line)
      endLine*: int # End line (1-based, 0 means current line)
    of claDeleteLines:
      deleteHasRange*: bool # Whether a line range is specified
      deleteIsGlobal*: bool # Whether % prefix (all lines)
      deleteStartLine*: int # Start line (1-based, 0 means current line)
      deleteEndLine*: int # End line (1-based, 0 means current line)
    of claHelp:
      topic*: Option[string]
    of claVSplit:
      vsplitFilename*: Option[string]
    of claHSplit:
      hsplitFilename*: Option[string]
    of claNew:
      discard
    of claVnew:
      discard
    of claBufferNext, claBufferPrev, claBufferFirst, claBufferLast:
      discard
    of claBufferDelete:
      forceBufferDelete*: bool # true for :bd!
    of claBuffer:
      bufferArg*: string # Buffer number or name
    of claStripWhitespace:
      discard
    of claFiler:
      filerPath*: Option[string] # Optional path to open in filer
    of claLogViewer:
      discard
    of claQuickRun:
      discard
    of claBufferManager:
      discard
    of claBackupManager:
      discard
    of claRecentFile:
      discard
    of claClearSearchHighlight:
      discard
    of claShellCommand:
      shellCommand*: string
    of claBackground:
      discard
    of claJumpList:
      discard
    of claChanges:
      discard
    of claBookmarks:
      discard
    of claConflictNext:
      discard
    of claConflictPrev:
      discard
    of claBuild:
      discard
    of claDebug:
      discard
    of claConfig:
      discard
    of claPutConfigFile:
      discard
    of claMan:
      manPage*: string # Manual page name
    of claTheme:
      themeName*: string # Theme name
    of claLspLog:
      discard
    of claLspFormat:
      discard
    of claLspRestart:
      discard
    of claLspFold:
      discard
    of claLspExecuteCommand:
      lspCommand*: string # LSP command to execute
      lspCommandArgs*: seq[string] # LSP command arguments
    of claLspCallHierarchyIncoming:
      discard
    of claLspCallHierarchyOutgoing:
      discard
    of claTerminal:
      terminalCommand*: string # Optional command (empty = default shell)
    of claMap, claNmap, claImap, claVmap, claRmap, claCmap:
      mapLhs*: string
      mapRhs*: string
      noremap*: bool ## True when the source was a :noremap-family command
    of claNoremap, claNnoremap, claInoremap, claVnoremap, claCnoremap:
      # The executor folds these into the base map kind above (carrying
      # noremap=true); a result never actually holds these kinds. Present only
      # so the variant stays exhaustive over CommandLineAction.
      discard
    of claUnmap, claNunmap, claIunmap, claVunmap, claRunmap, claCunmap:
      unmapLhs*: string
    of claMapclear, claNmapclear, claImapclear, claVmapclear, claRmapclear, claCmapclear:
      discard
    of claOnlyWindow:
      discard
    of claEditConfigFile:
      discard
    of claFileTree:
      fileTreePath*: Option[string] # Optional root path for file tree
    of claCquit:
      discard
    of claUnknown:
      errorMessage*: string

# Actions that require arguments (cannot be executed immediately)
# All other actions are considered no-argument actions
const ArgumentRequiredActions* = {
  claEdit, # requires filename
  claGoto, # requires line number
  claSet, # requires option name
  claSubstitute, # requires pattern
  claBuffer, # requires buffer number/name
  claShellCommand, # requires command
  claMan, # requires page name
  claTheme, # requires theme name
  claLspExecuteCommand, # requires command
  claVSplit, # optional but user may want to specify file
  claHSplit, # optional but user may want to specify file
  claFiler, # optional but user may want to specify path
  claTerminal, # optional but user may want to specify command
  claFileTree, # optional but user may want to specify path
  claMap, # requires lhs and rhs
  claNmap, # requires lhs and rhs
  claImap, # requires lhs and rhs
  claVmap, # requires lhs and rhs
  claRmap, # requires lhs and rhs
  claCmap, # requires lhs and rhs
  claNoremap, # requires lhs and rhs
  claNnoremap, # requires lhs and rhs
  claInoremap, # requires lhs and rhs
  claVnoremap, # requires lhs and rhs
  claCnoremap, # requires lhs and rhs
  claUnmap, # requires lhs
  claNunmap, # requires lhs
  claIunmap, # requires lhs
  claVunmap, # requires lhs
  claRunmap, # requires lhs
  claCunmap, # requires lhs
  claUnknown, # invalid command
}

proc isNoArgumentAction*(parser: CommandLineParser, command: string): bool =
  ## Check if a command requires no arguments based on its action
  ## Returns true for actions not in ArgumentRequiredActions
  if command in parser.aliases:
    return parser.aliases[command] notin ArgumentRequiredActions
  if command in parser.shellCommands:
    return false # Custom commands may accept arguments
  return false
