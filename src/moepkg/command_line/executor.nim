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

## Executes a ParsedCommand and returns a CommandLineResult variant. The
## large case dispatch lives here; pure pattern parsing lives in
## substitute_parser/delete_parser, while string -> ParsedCommand conversion
## lives in parser.

import std/[options, strutils]

import types, substitute_parser, delete_parser

proc execute*(parser: CommandLineParser, cmd: ParsedCommand): CommandLineResult =
  ## Execute a parsed command and return the result
  case cmd.action
  of claQuit:
    return CommandLineResult(kind: claQuit, forceQuit: "force" in cmd.flags)
  of claQuitAll:
    return CommandLineResult(kind: claQuitAll, forceQuitAll: "force" in cmd.flags)
  of claSave:
    return CommandLineResult(
      kind: claSave,
      filename:
        if cmd.args.len > 0:
          some(cmd.args[0])
        else:
          none(string),
      forceSave: "force" in cmd.flags,
    )
  of claSaveAll:
    return CommandLineResult(kind: claSaveAll, forceSaveAll: "force" in cmd.flags)
  of claSaveAndQuit:
    return CommandLineResult(
      kind: claSaveAndQuit,
      saveFilename:
        if cmd.args.len > 0:
          some(cmd.args[0])
        else:
          none(string),
      forceSaveAndQuit: "force" in cmd.flags,
    )
  of claSaveIfModifiedAndQuit:
    return CommandLineResult(
      kind: claSaveIfModifiedAndQuit,
      saveFilename:
        if cmd.args.len > 0:
          some(cmd.args[0])
        else:
          none(string),
      forceSaveAndQuit: "force" in cmd.flags,
    )
  of claSaveAllAndQuit:
    return CommandLineResult(
      kind: claSaveAllAndQuit, forceSaveAllAndQuit: "force" in cmd.flags
    )
  of claEdit:
    return CommandLineResult(
      kind: claEdit,
      editFilename:
        if cmd.args.len > 0:
          some(cmd.args[0])
        else:
          none(string),
      forceEdit: "force" in cmd.flags,
    )
  of claEnew:
    return CommandLineResult(kind: claEnew)
  of claGoto:
    if cmd.args.len > 0:
      try:
        let lineNum = parseInt(cmd.args[0])
        return CommandLineResult(kind: claGoto, lineNumber: lineNum)
      except ValueError:
        return CommandLineResult(kind: claUnknown, errorMessage: "Invalid line number")
    else:
      return
        CommandLineResult(kind: claUnknown, errorMessage: "No line number specified")
  of claSet:
    if cmd.args.len > 0:
      let option = cmd.args[0]
      # Parse set command (e.g., "set number", "set tabstop=4")
      if "=" in option:
        let parts = option.split("=", 1)
        return CommandLineResult(kind: claSet, option: parts[0], value: some(parts[1]))
      else:
        return CommandLineResult(kind: claSet, option: option, value: none(string))
    else:
      return CommandLineResult(kind: claUnknown, errorMessage: "No option specified")
  of claDeleteLines:
    # Parse delete command using parseDeleteCommand
    if cmd.args.len > 0:
      let parsed = parseDeleteCommand(":" & cmd.args[0])
      if not parsed.isValid:
        return CommandLineResult(
          kind: claUnknown, errorMessage: "Invalid delete command format"
        )
      return CommandLineResult(
        kind: claDeleteLines,
        deleteHasRange: parsed.hasRange,
        deleteIsGlobal: parsed.isGlobal,
        deleteStartLine: parsed.startLine,
        deleteEndLine: parsed.endLine,
      )
    else:
      # Simple :d with no range — delete current line
      return CommandLineResult(kind: claDeleteLines)
  of claSubstitute:
    # Parse substitute command using parseSubstituteCommand
    if cmd.args.len > 0:
      let parsed = parseSubstituteCommand(":" & cmd.args[0])
      if not parsed.isValid:
        return CommandLineResult(
          kind: claUnknown, errorMessage: "Invalid substitute command format"
        )
      if parsed.pattern.len == 0:
        return CommandLineResult(
          kind: claUnknown, errorMessage: "Pattern required for substitute"
        )
      return CommandLineResult(
        kind: claSubstitute,
        pattern: parsed.pattern,
        replacement: parsed.replacement,
        substituteFlags: parsed.flags,
        hasRange: parsed.hasRange,
        isGlobal: parsed.isGlobal,
        startLine: parsed.startLine,
        endLine: parsed.endLine,
      )
    else:
      return CommandLineResult(
        kind: claUnknown, errorMessage: "Invalid substitute command format"
      )
  of claHelp:
    return CommandLineResult(
      kind: claHelp,
      topic:
        if cmd.args.len > 0:
          some(cmd.args[0])
        else:
          none(string),
    )
  of claVSplit:
    return CommandLineResult(
      kind: claVSplit,
      vsplitFilename:
        if cmd.args.len > 0:
          some(cmd.args[0])
        else:
          none(string),
    )
  of claHSplit:
    return CommandLineResult(
      kind: claHSplit,
      hsplitFilename:
        if cmd.args.len > 0:
          some(cmd.args[0])
        else:
          none(string),
    )
  of claNew:
    return CommandLineResult(kind: claNew)
  of claVnew:
    return CommandLineResult(kind: claVnew)
  of claBufferNext:
    return CommandLineResult(kind: claBufferNext)
  of claBufferPrev:
    return CommandLineResult(kind: claBufferPrev)
  of claBufferFirst:
    return CommandLineResult(kind: claBufferFirst)
  of claBufferLast:
    return CommandLineResult(kind: claBufferLast)
  of claBufferDelete:
    return
      CommandLineResult(kind: claBufferDelete, forceBufferDelete: "force" in cmd.flags)
  of claBuffer:
    if cmd.args.len > 0:
      return CommandLineResult(kind: claBuffer, bufferArg: cmd.args[0])
    else:
      return
        CommandLineResult(kind: claUnknown, errorMessage: "E86: Buffer name required")
  of claStripWhitespace:
    return CommandLineResult(kind: claStripWhitespace)
  of claFiler:
    return CommandLineResult(
      kind: claFiler,
      filerPath:
        if cmd.args.len > 0:
          some(cmd.args[0])
        else:
          none(string),
    )
  of claLogViewer:
    return CommandLineResult(kind: claLogViewer)
  of claQuickRun:
    return CommandLineResult(kind: claQuickRun)
  of claBufferManager:
    return CommandLineResult(kind: claBufferManager)
  of claBackupManager:
    return CommandLineResult(kind: claBackupManager)
  of claRecentFile:
    return CommandLineResult(kind: claRecentFile)
  of claClearSearchHighlight:
    return CommandLineResult(kind: claClearSearchHighlight)
  of claShellCommand:
    if cmd.args.len > 0 and cmd.args[0].len > 0:
      return CommandLineResult(kind: claShellCommand, shellCommand: cmd.args[0])
    else:
      return
        CommandLineResult(kind: claUnknown, errorMessage: "No shell command specified")
  of claBackground:
    return CommandLineResult(kind: claBackground)
  of claJumpList:
    return CommandLineResult(kind: claJumpList)
  of claChanges:
    return CommandLineResult(kind: claChanges)
  of claBookmarks:
    return CommandLineResult(kind: claBookmarks)
  of claConflictNext:
    return CommandLineResult(kind: claConflictNext)
  of claConflictPrev:
    return CommandLineResult(kind: claConflictPrev)
  of claBuild:
    return CommandLineResult(kind: claBuild)
  of claDebug:
    return CommandLineResult(kind: claDebug)
  of claConfig:
    return CommandLineResult(kind: claConfig)
  of claPutConfigFile:
    return CommandLineResult(kind: claPutConfigFile)
  of claMan:
    if cmd.args.len > 0:
      return CommandLineResult(kind: claMan, manPage: cmd.args[0])
    else:
      return
        CommandLineResult(kind: claUnknown, errorMessage: "Manual page name required")
  of claTheme:
    if cmd.args.len > 0:
      return CommandLineResult(kind: claTheme, themeName: cmd.args[0])
    else:
      return CommandLineResult(kind: claUnknown, errorMessage: "Theme name required")
  of claLspLog:
    return CommandLineResult(kind: claLspLog)
  of claLspFormat:
    return CommandLineResult(kind: claLspFormat)
  of claLspRestart:
    return CommandLineResult(kind: claLspRestart)
  of claLspFold:
    return CommandLineResult(kind: claLspFold)
  of claLspExecuteCommand:
    if cmd.args.len > 0:
      let args =
        if cmd.args.len > 1:
          cmd.args[1 ..^ 1]
        else:
          @[]
      return CommandLineResult(
        kind: claLspExecuteCommand, lspCommand: cmd.args[0], lspCommandArgs: args
      )
    else:
      return CommandLineResult(kind: claUnknown, errorMessage: "LSP command required")
  of claLspCallHierarchyIncoming:
    return CommandLineResult(kind: claLspCallHierarchyIncoming)
  of claLspCallHierarchyOutgoing:
    return CommandLineResult(kind: claLspCallHierarchyOutgoing)
  of claTerminal:
    let termCmd =
      if cmd.args.len > 0:
        cmd.args.join(" ")
      else:
        ""
    return CommandLineResult(kind: claTerminal, terminalCommand: termCmd)
  of claMap, claNmap, claImap, claVmap, claRmap, claCmap, claNoremap, claNnoremap,
      claInoremap, claVnoremap, claCnoremap:
    # Fold the :noremap family onto its base map kind, carrying noremap=true so
    # the downstream handler shape stays unchanged. (Nim forbids constructing a
    # variant with a runtime discriminant, hence the explicit literal cases.)
    let noremap =
      cmd.action in {claNoremap, claNnoremap, claInoremap, claVnoremap, claCnoremap}
    if cmd.args.len == 0:
      # No arguments: list mappings
      case cmd.action
      of claMap, claNoremap:
        return CommandLineResult(kind: claMap, mapLhs: "", mapRhs: "", noremap: noremap)
      of claNmap, claNnoremap:
        return
          CommandLineResult(kind: claNmap, mapLhs: "", mapRhs: "", noremap: noremap)
      of claImap, claInoremap:
        return
          CommandLineResult(kind: claImap, mapLhs: "", mapRhs: "", noremap: noremap)
      of claVmap, claVnoremap:
        return
          CommandLineResult(kind: claVmap, mapLhs: "", mapRhs: "", noremap: noremap)
      of claRmap:
        return
          CommandLineResult(kind: claRmap, mapLhs: "", mapRhs: "", noremap: noremap)
      of claCmap, claCnoremap:
        return
          CommandLineResult(kind: claCmap, mapLhs: "", mapRhs: "", noremap: noremap)
      else:
        discard
    if cmd.args.len == 1:
      # Vim-compat: `:nmap <prefix>` lists mappings whose lhs starts with
      # <prefix>. Signal that by leaving mapRhs empty; the handler routes an
      # empty rhs to hrMapList with the prefix.
      let prefix = cmd.args[0]
      case cmd.action
      of claMap, claNoremap:
        return
          CommandLineResult(kind: claMap, mapLhs: prefix, mapRhs: "", noremap: noremap)
      of claNmap, claNnoremap:
        return
          CommandLineResult(kind: claNmap, mapLhs: prefix, mapRhs: "", noremap: noremap)
      of claImap, claInoremap:
        return
          CommandLineResult(kind: claImap, mapLhs: prefix, mapRhs: "", noremap: noremap)
      of claVmap, claVnoremap:
        return
          CommandLineResult(kind: claVmap, mapLhs: prefix, mapRhs: "", noremap: noremap)
      of claRmap:
        return
          CommandLineResult(kind: claRmap, mapLhs: prefix, mapRhs: "", noremap: noremap)
      of claCmap, claCnoremap:
        return
          CommandLineResult(kind: claCmap, mapLhs: prefix, mapRhs: "", noremap: noremap)
      else:
        discard
    let lhs = cmd.args[0]
    # Read the RHS verbatim from rawText — tokenize+join would lose tabs.
    let rhs = block:
      var i = 0
      if i < cmd.rawText.len and cmd.rawText[i] == ':':
        inc i
      while i < cmd.rawText.len and cmd.rawText[i] notin Whitespace:
        inc i
      while i < cmd.rawText.len and cmd.rawText[i] in Whitespace:
        inc i
      if i + lhs.len <= cmd.rawText.len and cmd.rawText[i ..< i + lhs.len] == lhs:
        i += lhs.len
        while i < cmd.rawText.len and cmd.rawText[i] in Whitespace:
          inc i
        cmd.rawText[i ..^ 1]
      else:
        cmd.args[1 ..^ 1].join(" ")
    case cmd.action
    of claMap, claNoremap:
      return CommandLineResult(kind: claMap, mapLhs: lhs, mapRhs: rhs, noremap: noremap)
    of claNmap, claNnoremap:
      return
        CommandLineResult(kind: claNmap, mapLhs: lhs, mapRhs: rhs, noremap: noremap)
    of claImap, claInoremap:
      return
        CommandLineResult(kind: claImap, mapLhs: lhs, mapRhs: rhs, noremap: noremap)
    of claVmap, claVnoremap:
      return
        CommandLineResult(kind: claVmap, mapLhs: lhs, mapRhs: rhs, noremap: noremap)
    of claRmap:
      return
        CommandLineResult(kind: claRmap, mapLhs: lhs, mapRhs: rhs, noremap: noremap)
    of claCmap, claCnoremap:
      return
        CommandLineResult(kind: claCmap, mapLhs: lhs, mapRhs: rhs, noremap: noremap)
    else:
      discard
  of claUnmap, claNunmap, claIunmap, claVunmap, claRunmap, claCunmap:
    if cmd.args.len < 1:
      let cmdName =
        case cmd.action
        of claNunmap: "nunmap"
        of claIunmap: "iunmap"
        of claVunmap: "vunmap"
        of claRunmap: "runmap"
        of claCunmap: "cunmap"
        else: "unmap"
      return CommandLineResult(
        kind: claUnknown, errorMessage: "Usage: :" & cmdName & " {lhs}"
      )
    let lhs = cmd.args[0]
    case cmd.action
    of claUnmap:
      return CommandLineResult(kind: claUnmap, unmapLhs: lhs)
    of claNunmap:
      return CommandLineResult(kind: claNunmap, unmapLhs: lhs)
    of claIunmap:
      return CommandLineResult(kind: claIunmap, unmapLhs: lhs)
    of claVunmap:
      return CommandLineResult(kind: claVunmap, unmapLhs: lhs)
    of claRunmap:
      return CommandLineResult(kind: claRunmap, unmapLhs: lhs)
    of claCunmap:
      return CommandLineResult(kind: claCunmap, unmapLhs: lhs)
    else:
      discard
  of claMapclear:
    return CommandLineResult(kind: claMapclear)
  of claNmapclear:
    return CommandLineResult(kind: claNmapclear)
  of claImapclear:
    return CommandLineResult(kind: claImapclear)
  of claVmapclear:
    return CommandLineResult(kind: claVmapclear)
  of claRmapclear:
    return CommandLineResult(kind: claRmapclear)
  of claCmapclear:
    return CommandLineResult(kind: claCmapclear)
  of claOnlyWindow:
    return CommandLineResult(kind: claOnlyWindow)
  of claEditConfigFile:
    return CommandLineResult(kind: claEditConfigFile)
  of claFileTree:
    return CommandLineResult(
      kind: claFileTree,
      fileTreePath:
        if cmd.args.len > 0:
          some(cmd.args[0])
        else:
          none(string),
    )
  of claCquit:
    return CommandLineResult(kind: claCquit)
  of claUnknown:
    return CommandLineResult(
      kind: claUnknown, errorMessage: "Not an editor command: " & cmd.rawText
    )
