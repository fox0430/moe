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

## Command mode handler
##
## This module handles commands specific to Command mode, including:
## - File operations (:w, :e, :q)
## - Search and replace (:s)
## - Settings (:set)
## - Navigation (:123 for line jumping)

import std/[options, strutils, os]

import pkg/results

import ../[buffer, gapbuffer, modes, commandline, commandconfig, commandregistry]

type
  BoolSettingOption* = enum
    ## Boolean setting options that can be toggled via :set command
    bsoNumber # line numbers
    bsoCurrentNumber # current line number
    bsoCursorLine # cursor line highlight
    bsoStatusLine # status line
    bsoSyntax # syntax highlighting
    bsoIndentationLines # indentation guide lines
    bsoAutoIndent # auto indent
    bsoAutoCloseParen # auto close parentheses
    bsoAutoDeleteParen # auto delete parentheses
    bsoClipboard # system clipboard
    bsoSmoothScroll # smooth scroll
    bsoLiveReloadOfConf # live reload of config
    bsoShowIcons # filer icons
    bsoHighlightCurrentLine # highlight current line
    bsoHighlightCurrentWord # highlight current word
    bsoHighlightFullWidthSpace # highlight full-width space
    bsoHighlightPairOfParen # highlight pair of parentheses
    bsoMultipleStatusLine # multiple status line
    bsoIgnoreCase # ignore case in search
    bsoSmartCase # smart case in search
    bsoIncSearch # incremental search
    bsoHlSearch # highlight search results
    bsoBuildOnSave # build on save
    bsoShowGitInactive # show git branch in inactive window

  IntSettingOption* = enum
    ## Integer setting options that can be set via :set command
    isoTabStop # tab stop width

  FloatSettingOption* = enum
    ## Float setting options that can be set via :set command
    fsoScrollFriction # smooth scroll friction (comfortable-motion compatible)
    fsoScrollAirDrag # smooth scroll air drag (comfortable-motion compatible)

  CommandModeResultKind* = enum
    cmrQuit # Application should quit
    cmrCloseWindow # Close current window
    cmrModeSwitch # Switch to different mode
    cmrMessage # Show status message
    cmrGotoLine # Jump to specific line
    cmrVSplit # Vertical split window
    cmrHSplit # Horizontal split window
    cmrNew # Create new empty buffer in horizontal split
    cmrVnew # Create new empty buffer in vertical split
    cmrEnew # Create new empty buffer
    cmrEdit # Edit/open file in current window
    cmrSetBoolOption # Set boolean option
    cmrSetIntOption # Set integer option
    cmrSetFloatOption # Set float option
    cmrSave # Save file
    cmrSaveAndQuit # Save file and quit
    cmrBufferNext # Switch to next buffer
    cmrBufferPrev # Switch to previous buffer
    cmrBufferFirst # Switch to first buffer
    cmrBufferLast # Switch to last buffer
    cmrBuffer # Switch to buffer by number or name
    cmrBufferDelete # Delete current buffer
    cmrStripWhitespace # Remove trailing whitespace
    cmrFiler # Open file explorer
    cmrLogViewer # Open log viewer
    cmrHelpViewer # Open help viewer
    cmrQuickRun # Run the current buffer
    cmrBufferManager # Open buffer manager
    cmrBackupManager # Open backup manager
    cmrRecentFile # Open recent file selection mode
    cmrClearSearchHighlight # Clear search highlighting (:noh)
    cmrShellCommand # Execute shell command (:!)
    cmrBackground # Pause editor and show terminal (:bg)
    cmrJumpList # Show jump list (:ju, :jump)
    cmrBuild # Build current buffer (:build)
    cmrDebug # Open debug mode (:debug)
    cmrConfig # Open configuration mode (:conf)
    cmrPutConfigFile # Write sample config file (:putConfigFile)
    cmrMan # Show manual page (:man)
    cmrTheme # Change color theme (:theme)
    cmrLspLog # Open LSP log viewer (:lspLog)
    cmrLspFormat # LSP document formatting (:lspFormat)
    cmrLspRestart # Restart LSP server (:lspRestart)
    cmrLspForceRestart # Force restart LSP server (:lspForceRestart)
    cmrLspFold # LSP folding range (:lspFold)
    cmrLspExecuteCommand # LSP execute command (:lspExeCommand)
    cmrLspCallHierarchyIncoming # LSP incoming calls (:lspCallHierarchyIncoming)
    cmrLspCallHierarchyOutgoing # LSP outgoing calls (:lspCallHierarchyOutgoing)
    cmrSubstitute # Search and replace (:s)
    cmrError # Command error

  CommandModeHandler* = ref object ## Handler for Command mode specific commands
    parser*: CommandLineParser
    config*: CommandConfig
    commandRegistry*: CommandRegistry

  CommandModeResult* = object ## Result of command mode execution
    case kind*: CommandModeResultKind
    of cmrQuit:
      forceQuit*: bool
    of cmrCloseWindow:
      forceClose*: bool
    of cmrModeSwitch:
      targetMode*: EditorMode
    of cmrMessage:
      message*: string
    of cmrGotoLine:
      lineNumber*: int
    of cmrVSplit:
      vsplitFilename*: Option[string]
    of cmrHSplit:
      hsplitFilename*: Option[string]
    of cmrNew:
      discard
    of cmrVnew:
      discard
    of cmrEnew:
      discard
    of cmrEdit:
      editFilename*: string
    of cmrSetBoolOption:
      boolOption*: BoolSettingOption
      boolValue*: bool
    of cmrSetIntOption:
      intOption*: IntSettingOption
      intValue*: int
    of cmrSetFloatOption:
      floatOption*: FloatSettingOption
      floatValue*: float
    of cmrSave:
      saveFilename*: Option[string]
      forceSave*: bool
    of cmrSaveAndQuit:
      saveAndQuitFilename*: Option[string]
      forceSaveAndQuit*: bool
    of cmrBufferNext, cmrBufferPrev, cmrBufferFirst, cmrBufferLast:
      discard
    of cmrBuffer:
      bufferArg*: string # Buffer number or name
    of cmrBufferDelete:
      forceBufferDelete*: bool
    of cmrStripWhitespace:
      strippedLineCount*: int
    of cmrFiler:
      filerPath*: Option[string] # Optional path for filer
    of cmrLogViewer:
      discard
    of cmrHelpViewer:
      discard
    of cmrQuickRun:
      discard
    of cmrBufferManager:
      discard
    of cmrBackupManager:
      discard
    of cmrRecentFile:
      discard
    of cmrClearSearchHighlight:
      discard
    of cmrShellCommand:
      shellCommand*: string
    of cmrBackground:
      discard
    of cmrJumpList:
      discard
    of cmrBuild:
      discard
    of cmrDebug:
      discard
    of cmrConfig:
      discard
    of cmrPutConfigFile:
      discard
    of cmrMan:
      manPage*: string
    of cmrTheme:
      themeName*: string
    of cmrLspLog:
      discard
    of cmrLspFormat:
      discard
    of cmrLspRestart:
      discard
    of cmrLspForceRestart:
      discard
    of cmrLspFold:
      discard
    of cmrLspExecuteCommand:
      lspCommand*: string
    of cmrLspCallHierarchyIncoming:
      discard
    of cmrLspCallHierarchyOutgoing:
      discard
    of cmrSubstitute:
      substitutePattern*: string
      substituteReplacement*: string
      substituteGlobal*: bool # true for /g flag
      substituteCount*: int # number of replacements made
    of cmrError:
      errorMessage*: string

proc newCommandModeHandler*(
    parser: CommandLineParser, config: CommandConfig, commandRegistry: CommandRegistry
): CommandModeHandler =
  ## Create a new Command mode handler
  CommandModeHandler(parser: parser, config: config, commandRegistry: commandRegistry)

proc executeQuit*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    force: bool,
    isSharedBuffer: bool = false,
): CommandModeResult =
  ## Execute quit command (:q, :q!) - now closes current window
  ## If isSharedBuffer is true, skip the isModified check since buffer is shared across windows
  if not force and not isSharedBuffer:
    # Check if there are unsaved changes
    if buffer.isModified:
      return CommandModeResult(
        kind: cmrError, errorMessage: "No write since last change (add ! to override)"
      )

  return CommandModeResult(kind: cmrCloseWindow, forceClose: force)

proc executeSave*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    filename: Option[string],
    force: bool,
): CommandModeResult =
  ## Execute save command (:w, :w!)
  ## Returns cmrSave to signal that the file should be saved
  ## The actual save operation is performed by the editor
  return CommandModeResult(kind: cmrSave, saveFilename: filename, forceSave: force)

proc executeSaveAndQuit*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    filename: Option[string],
    force: bool,
): CommandModeResult =
  ## Execute save and quit command (:wq, :x)
  ## Returns cmrSaveAndQuit to signal that the file should be saved and editor should quit
  ## The actual save operation is performed by the editor
  return CommandModeResult(
    kind: cmrSaveAndQuit, saveAndQuitFilename: filename, forceSaveAndQuit: force
  )

proc executeQuitAll*(
    handler: CommandModeHandler, buffer: TextBuffer, force: bool
): CommandModeResult =
  ## Execute quit all command (:qa, :qa!) - closes all windows and quits
  if not force:
    # Check if there are unsaved changes
    if buffer.isModified:
      return CommandModeResult(
        kind: cmrError, errorMessage: "No write since last change (add ! to override)"
      )

  # Return cmrQuit to signal immediate editor quit
  return CommandModeResult(kind: cmrQuit, forceQuit: force)

proc executeEdit*(
    handler: CommandModeHandler, buffer: TextBuffer, filename: string
): CommandModeResult =
  ## Execute edit command (:e filename)
  # If path is a directory, open in Filer mode
  if dirExists(filename):
    return CommandModeResult(kind: cmrFiler, filerPath: some(absolutePath(filename)))
  # Open the file in the current window
  return CommandModeResult(kind: cmrEdit, editFilename: absolutePath(filename))

proc executeGotoLine*(
    handler: CommandModeHandler, buffer: TextBuffer, lineNumber: int
): CommandModeResult =
  ## Execute goto line command (:123)
  if lineNumber <= 0:
    return CommandModeResult(kind: cmrError, errorMessage: "Invalid line number")

  # Check if line number is beyond the buffer length
  if lineNumber > buffer.len:
    return CommandModeResult(
      kind: cmrError, errorMessage: "Line number exceeds buffer length"
    )

  return CommandModeResult(kind: cmrGotoLine, lineNumber: lineNumber)

proc executeSet*(
    handler: CommandModeHandler, option: string, value: Option[string]
): CommandModeResult =
  ## Execute set command (:set option=value)
  let opt = option.toLower

  # Boolean options - enable
  case opt
  # Line numbers
  of "number", "nu":
    return
      CommandModeResult(kind: cmrSetBoolOption, boolOption: bsoNumber, boolValue: true)
  of "nonumber", "nonu":
    return
      CommandModeResult(kind: cmrSetBoolOption, boolOption: bsoNumber, boolValue: false)
  # Current line number
  of "currentnumber", "cnu":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoCurrentNumber, boolValue: true
    )
  of "nocurrentnumber", "nocnu":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoCurrentNumber, boolValue: false
    )
  # Cursor line
  of "cursorline", "cul":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoCursorLine, boolValue: true
    )
  of "nocursorline", "nocul":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoCursorLine, boolValue: false
    )
  # Status line
  of "statusline", "stl":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoStatusLine, boolValue: true
    )
  of "nostatusline", "nostl":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoStatusLine, boolValue: false
    )
  # Syntax highlighting
  of "syntax", "syn":
    return
      CommandModeResult(kind: cmrSetBoolOption, boolOption: bsoSyntax, boolValue: true)
  of "nosyntax", "nosyn":
    return
      CommandModeResult(kind: cmrSetBoolOption, boolOption: bsoSyntax, boolValue: false)
  # Indentation lines
  of "indentationlines", "indl":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoIndentationLines, boolValue: true
    )
  of "noindentationlines", "noindl":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoIndentationLines, boolValue: false
    )
  # Auto indent
  of "autoindent", "ai":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoAutoIndent, boolValue: true
    )
  of "noautoindent", "noai":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoAutoIndent, boolValue: false
    )
  # Auto close paren
  of "autocloseparen", "acp":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoAutoCloseParen, boolValue: true
    )
  of "noautocloseparen", "noacp":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoAutoCloseParen, boolValue: false
    )
  # Auto delete paren
  of "autodeleteparen", "adp":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoAutoDeleteParen, boolValue: true
    )
  of "noautodeleteparen", "noadp":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoAutoDeleteParen, boolValue: false
    )
  # Clipboard
  of "clipboard", "cb":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoClipboard, boolValue: true
    )
  of "noclipboard", "nocb":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoClipboard, boolValue: false
    )
  # Smooth scroll
  of "smoothscroll", "sms":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoSmoothScroll, boolValue: true
    )
  of "nosmoothscroll", "nosms":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoSmoothScroll, boolValue: false
    )
  # Live reload of config
  of "livereload", "lr":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoLiveReloadOfConf, boolValue: true
    )
  of "nolivereload", "nolr":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoLiveReloadOfConf, boolValue: false
    )
  # Filer icons
  of "icon", "icons":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoShowIcons, boolValue: true
    )
  of "noicon", "noicons":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoShowIcons, boolValue: false
    )
  # Highlight current line
  of "highlightcurrentline", "hcl":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoHighlightCurrentLine, boolValue: true
    )
  of "nohighlightcurrentline", "nohcl":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoHighlightCurrentLine, boolValue: false
    )
  # Highlight current word
  of "highlightcurrentword", "hcw":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoHighlightCurrentWord, boolValue: true
    )
  of "nohighlightcurrentword", "nohcw":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoHighlightCurrentWord, boolValue: false
    )
  # Highlight full width space
  of "highlightfullspace", "hfs":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoHighlightFullWidthSpace, boolValue: true
    )
  of "nohighlightfullspace", "nohfs":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoHighlightFullWidthSpace, boolValue: false
    )
  # Highlight pair of paren
  of "highlightparen", "hp":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoHighlightPairOfParen, boolValue: true
    )
  of "nohighlightparen", "nohp":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoHighlightPairOfParen, boolValue: false
    )
  # Multiple status line
  of "multistatusline", "msl":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoMultipleStatusLine, boolValue: true
    )
  of "nomultistatusline", "nomsl":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoMultipleStatusLine, boolValue: false
    )
  # Ignore case
  of "ignorecase", "ic":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoIgnoreCase, boolValue: true
    )
  of "noignorecase", "noic":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoIgnoreCase, boolValue: false
    )
  # Smart case
  of "smartcase", "scs":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoSmartCase, boolValue: true
    )
  of "nosmartcase", "noscs":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoSmartCase, boolValue: false
    )
  # Incremental search
  of "incsearch", "is":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoIncSearch, boolValue: true
    )
  of "noincsearch", "nois":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoIncSearch, boolValue: false
    )
  # Highlight search
  of "hlsearch", "hls":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoHlSearch, boolValue: true
    )
  of "nohlsearch", "nohls":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoHlSearch, boolValue: false
    )
  # Build on save
  of "buildonsave", "bos":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoBuildOnSave, boolValue: true
    )
  of "nobuildonsave", "nobos":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoBuildOnSave, boolValue: false
    )
  # Show git in inactive window
  of "showgitinactive", "sgi":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoShowGitInactive, boolValue: true
    )
  of "noshowgitinactive", "nosgi":
    return CommandModeResult(
      kind: cmrSetBoolOption, boolOption: bsoShowGitInactive, boolValue: false
    )
  # Tab stop (integer option)
  of "tabstop", "ts":
    if value.isSome:
      try:
        let intVal = parseInt(value.get)
        if intVal > 0:
          return CommandModeResult(
            kind: cmrSetIntOption, intOption: isoTabStop, intValue: intVal
          )
        else:
          return
            CommandModeResult(kind: cmrError, errorMessage: "tabstop must be positive")
      except ValueError:
        return
          CommandModeResult(kind: cmrError, errorMessage: "Invalid value for tabstop")
    else:
      return CommandModeResult(
        kind: cmrError, errorMessage: "tabstop requires a value (e.g., tabstop=4)"
      )
  # Scroll friction (float option, comfortable-motion compatible)
  of "scrollfriction", "sfr":
    if value.isSome:
      try:
        let floatVal = parseFloat(value.get)
        if floatVal >= 0:
          return CommandModeResult(
            kind: cmrSetFloatOption,
            floatOption: fsoScrollFriction,
            floatValue: floatVal,
          )
        else:
          return CommandModeResult(
            kind: cmrError, errorMessage: "scrollfriction must be non-negative"
          )
      except ValueError:
        return CommandModeResult(
          kind: cmrError, errorMessage: "Invalid value for scrollfriction"
        )
    else:
      return CommandModeResult(
        kind: cmrError,
        errorMessage: "scrollfriction requires a value (e.g., scrollfriction=80.0)",
      )
  # Scroll air drag (float option, comfortable-motion compatible)
  of "scrollairdrag", "sad":
    if value.isSome:
      try:
        let floatVal = parseFloat(value.get)
        if floatVal >= 0:
          return CommandModeResult(
            kind: cmrSetFloatOption, floatOption: fsoScrollAirDrag, floatValue: floatVal
          )
        else:
          return CommandModeResult(
            kind: cmrError, errorMessage: "scrollairdrag must be non-negative"
          )
      except ValueError:
        return CommandModeResult(
          kind: cmrError, errorMessage: "Invalid value for scrollairdrag"
        )
    else:
      return CommandModeResult(
        kind: cmrError,
        errorMessage: "scrollairdrag requires a value (e.g., scrollairdrag=2.0)",
      )
  else:
    return CommandModeResult(kind: cmrError, errorMessage: "Unknown option: " & option)

proc executeHelp*(
    handler: CommandModeHandler, topic: Option[string]
): CommandModeResult =
  ## Execute help command (:help, :help topic)
  # Open the help viewer
  return CommandModeResult(kind: cmrHelpViewer)

proc executeVSplit*(
    handler: CommandModeHandler, filename: Option[string]
): CommandModeResult =
  ## Execute vertical split command (:vs, :vs filename)
  # If path is a directory, open in Filer mode
  if filename.isSome and dirExists(filename.get):
    return
      CommandModeResult(kind: cmrFiler, filerPath: some(absolutePath(filename.get)))
  return CommandModeResult(kind: cmrVSplit, vsplitFilename: filename)

proc executeHSplit*(
    handler: CommandModeHandler, filename: Option[string]
): CommandModeResult =
  ## Execute horizontal split command (:sp, :sp filename)
  # If path is a directory, open in Filer mode
  if filename.isSome and dirExists(filename.get):
    return
      CommandModeResult(kind: cmrFiler, filerPath: some(absolutePath(filename.get)))
  return CommandModeResult(kind: cmrHSplit, hsplitFilename: filename)

proc executeNew*(handler: CommandModeHandler): CommandModeResult =
  ## Execute new command (:new) - create new empty buffer in horizontal split
  return CommandModeResult(kind: cmrNew)

proc executeVnew*(handler: CommandModeHandler): CommandModeResult =
  ## Execute vnew command (:vnew) - create new empty buffer in vertical split
  return CommandModeResult(kind: cmrVnew)

proc executeEnew*(handler: CommandModeHandler): CommandModeResult =
  ## Execute enew command (:ene, :enew) - create new empty buffer
  return CommandModeResult(kind: cmrEnew)

proc executeBufferNext*(handler: CommandModeHandler): CommandModeResult =
  ## Execute bnext command (:bn, :bnext) - switch to next buffer
  return CommandModeResult(kind: cmrBufferNext)

proc executeBufferPrev*(handler: CommandModeHandler): CommandModeResult =
  ## Execute bprev command (:bp, :bprev) - switch to previous buffer
  return CommandModeResult(kind: cmrBufferPrev)

proc executeBufferFirst*(handler: CommandModeHandler): CommandModeResult =
  ## Execute bfirst command (:bf, :bfirst) - switch to first buffer
  return CommandModeResult(kind: cmrBufferFirst)

proc executeBufferLast*(handler: CommandModeHandler): CommandModeResult =
  ## Execute blast command (:bl, :blast) - switch to last buffer
  return CommandModeResult(kind: cmrBufferLast)

proc executeBuffer*(handler: CommandModeHandler, arg: string): CommandModeResult =
  ## Execute buffer command (:b N or :b name) - switch to buffer by number or name
  return CommandModeResult(kind: cmrBuffer, bufferArg: arg)

proc executeBufferDelete*(
    handler: CommandModeHandler, buffer: TextBuffer, force: bool
): CommandModeResult =
  ## Execute bdelete command (:bd, :bdelete) - delete current buffer
  if not force and buffer.isModified:
    return CommandModeResult(
      kind: cmrError, errorMessage: "No write since last change (add ! to override)"
    )
  return CommandModeResult(kind: cmrBufferDelete, forceBufferDelete: force)

proc executeStripWhitespace*(
    handler: CommandModeHandler, buffer: TextBuffer
): CommandModeResult =
  ## Execute stripwhitespace command (:stripwhitespace, :stripws)
  ## Removes trailing whitespace from all lines
  var strippedCount = 0
  for lineIdx in 0 ..< buffer.len:
    let line = buffer.getLine(lineIdx)
    let trimmed = line.strip(leading = false, trailing = true)
    if trimmed != line:
      buffer.gapBuffer.replaceLine(lineIdx, trimmed)
      strippedCount.inc
  return CommandModeResult(kind: cmrStripWhitespace, strippedLineCount: strippedCount)

proc executeQuickRun*(handler: CommandModeHandler): CommandModeResult =
  ## Execute quickrun command (:run, :quickrun, :qr)
  return CommandModeResult(kind: cmrQuickRun)

proc executeSubstitute*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    pattern: string,
    replacement: string,
    flags: string,
    hasRange: bool = false,
    isGlobalRange: bool = false,
    startLine: int = 0,
    endLine: int = 0,
    currentLine: int = 0,
): CommandModeResult =
  ## Execute substitute command (:s, :%s/pattern/replacement/flags)
  ## flags: "g" for global replacement (all occurrences), otherwise first only
  ## hasRange: true if a line range was specified (e.g., :1,10s/...)
  ## isGlobalRange: true if % prefix was used (all lines)
  ## startLine/endLine: line range (1-based, 0 means current line)
  ## currentLine: current cursor line (0-based)
  if pattern.len == 0:
    return CommandModeResult(kind: cmrError, errorMessage: "Pattern required")

  let isGlobal = "g" in flags
  var replaceCount = 0

  # Process escape sequences in replacement string using common utility
  let processedReplacement = processEscapeSequences(replacement)

  # Determine line range
  var rangeStart, rangeEnd: int
  if isGlobalRange:
    # % means all lines
    rangeStart = 0
    rangeEnd = buffer.len - 1
  elif hasRange:
    # Explicit range specified
    # Convert 1-based to 0-based, 0 means current line
    rangeStart =
      if startLine == 0:
        currentLine
      else:
        startLine - 1
    rangeEnd =
      if endLine == 0:
        currentLine
      else:
        endLine - 1
    # Validate range
    if rangeStart < 0:
      rangeStart = 0
    if rangeEnd >= buffer.len:
      rangeEnd = buffer.len - 1
    if rangeStart > rangeEnd:
      return CommandModeResult(
        kind: cmrError, errorMessage: "Invalid range: start line > end line"
      )
  else:
    # No range - current line only
    rangeStart = currentLine
    rangeEnd = currentLine

  # Begin transaction for all changes
  discard buffer.beginTransaction("substitute")

  # Search and replace in specified range
  for lineIdx in rangeStart .. rangeEnd:
    var line = buffer.getLine(lineIdx)
    var modified = false
    var newLine = ""
    var searchPos = 0

    while searchPos <= line.len:
      let idx = line.find(pattern, searchPos)
      if idx < 0:
        # No more matches - add rest of line
        newLine.add(line[searchPos ..^ 1])
        break

      # Add text before match
      if idx > searchPos:
        newLine.add(line[searchPos ..< idx])

      # Add replacement
      newLine.add(processedReplacement)
      replaceCount.inc
      modified = true

      # Move past the match
      searchPos = idx + pattern.len

      # If not global, only replace first occurrence per line
      if not isGlobal:
        newLine.add(line[searchPos ..^ 1])
        break

    # Update the line if modified
    if modified:
      buffer.gapBuffer.replaceLine(lineIdx, newLine)

  # Mark highlight as needing update since we bypassed normal change tracking
  if replaceCount > 0:
    buffer.highlightNeedsUpdate = true
    buffer.lastChangedLines = (0, buffer.len - 1) # Mark all lines as changed

  discard buffer.commitTransaction()

  if replaceCount == 0:
    return
      CommandModeResult(kind: cmrError, errorMessage: "Pattern not found: " & pattern)

  return CommandModeResult(
    kind: cmrSubstitute,
    substitutePattern: pattern,
    substituteReplacement: processedReplacement,
    substituteGlobal: isGlobal,
    substituteCount: replaceCount,
  )

proc handleCommandModeInput*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    commandText: string,
    isSharedBuffer: bool = false,
    currentLine: int = 0,
): CommandModeResult =
  ## Main entry point for handling Command mode input
  ## isSharedBuffer: true if the buffer is shared across multiple windows
  ## currentLine: current cursor line (0-based), used for range substitution with '.'

  if commandText.len <= 1: # Just ":"
    return CommandModeResult(kind: cmrModeSwitch, targetMode: EditorMode.Normal)

  # Parse and execute the command
  let cmdResult = handler.parser.parseAndExecute(commandText)

  case cmdResult.kind
  of claQuit:
    return handler.executeQuit(buffer, cmdResult.forceQuit, isSharedBuffer)
  of claQuitAll:
    return handler.executeQuitAll(buffer, cmdResult.forceQuitAll)
  of claSave:
    return handler.executeSave(buffer, cmdResult.filename, cmdResult.forceSave)
  of claSaveAll:
    # TODO: Handle save all (multiple buffers)
    return handler.executeSave(buffer, none(string), cmdResult.forceSaveAll)
  of claSaveAndQuit:
    return handler.executeSaveAndQuit(
      buffer, cmdResult.saveFilename, cmdResult.forceSaveAndQuit
    )
  of claSaveAllAndQuit:
    # TODO: Handle save all and quit
    return
      handler.executeSaveAndQuit(buffer, none(string), cmdResult.forceSaveAllAndQuit)
  of claEdit:
    return handler.executeEdit(buffer, cmdResult.editFilename)
  of claEnew:
    return handler.executeEnew()
  of claGoto:
    return handler.executeGotoLine(buffer, cmdResult.lineNumber)
  of claSet:
    return handler.executeSet(cmdResult.option, cmdResult.value)
  of claHelp:
    return handler.executeHelp(cmdResult.topic)
  of claVSplit:
    return handler.executeVSplit(cmdResult.vsplitFilename)
  of claHSplit:
    return handler.executeHSplit(cmdResult.hsplitFilename)
  of claNew:
    return handler.executeNew()
  of claVnew:
    return handler.executeVnew()
  of claBufferNext:
    return handler.executeBufferNext()
  of claBufferPrev:
    return handler.executeBufferPrev()
  of claBufferFirst:
    return handler.executeBufferFirst()
  of claBufferLast:
    return handler.executeBufferLast()
  of claBufferDelete:
    return handler.executeBufferDelete(buffer, cmdResult.forceBufferDelete)
  of claBuffer:
    return handler.executeBuffer(cmdResult.bufferArg)
  of claStripWhitespace:
    return handler.executeStripWhitespace(buffer)
  of claFiler:
    return CommandModeResult(kind: cmrFiler, filerPath: cmdResult.filerPath)
  of claLogViewer:
    return CommandModeResult(kind: cmrLogViewer)
  of claQuickRun:
    return handler.executeQuickRun()
  of claBufferManager:
    return CommandModeResult(kind: cmrBufferManager)
  of claBackupManager:
    return CommandModeResult(kind: cmrBackupManager)
  of claRecentFile:
    return CommandModeResult(kind: cmrRecentFile)
  of claClearSearchHighlight:
    return CommandModeResult(kind: cmrClearSearchHighlight)
  of claShellCommand:
    return
      CommandModeResult(kind: cmrShellCommand, shellCommand: cmdResult.shellCommand)
  of claBackground:
    return CommandModeResult(kind: cmrBackground)
  of claJumpList:
    return CommandModeResult(kind: cmrJumpList)
  of claBuild:
    return CommandModeResult(kind: cmrBuild)
  of claDebug:
    return CommandModeResult(kind: cmrDebug)
  of claConfig:
    return CommandModeResult(kind: cmrConfig)
  of claPutConfigFile:
    return CommandModeResult(kind: cmrPutConfigFile)
  of claMan:
    return CommandModeResult(kind: cmrMan, manPage: cmdResult.manPage)
  of claTheme:
    return CommandModeResult(kind: cmrTheme, themeName: cmdResult.themeName)
  of claLspLog:
    return CommandModeResult(kind: cmrLspLog)
  of claLspFormat:
    return CommandModeResult(kind: cmrLspFormat)
  of claLspRestart:
    return CommandModeResult(kind: cmrLspRestart)
  of claLspForceRestart:
    return CommandModeResult(kind: cmrLspForceRestart)
  of claLspFold:
    return CommandModeResult(kind: cmrLspFold)
  of claLspExecuteCommand:
    return
      CommandModeResult(kind: cmrLspExecuteCommand, lspCommand: cmdResult.lspCommand)
  of claLspCallHierarchyIncoming:
    return CommandModeResult(kind: cmrLspCallHierarchyIncoming)
  of claLspCallHierarchyOutgoing:
    return CommandModeResult(kind: cmrLspCallHierarchyOutgoing)
  of claSubstitute:
    return handler.executeSubstitute(
      buffer, cmdResult.pattern, cmdResult.replacement, cmdResult.substituteFlags,
      cmdResult.hasRange, cmdResult.isGlobal, cmdResult.startLine, cmdResult.endLine,
      currentLine,
    )
  of claUnknown:
    return CommandModeResult(kind: cmrError, errorMessage: cmdResult.errorMessage)

proc shouldQuit*(cmdResult: CommandModeResult): bool =
  ## Check if the application should quit
  cmdResult.kind == cmrQuit

proc shouldSwitchMode*(cmdResult: CommandModeResult): bool =
  ## Check if mode should be switched
  cmdResult.kind == cmrModeSwitch

proc getTargetMode*(cmdResult: CommandModeResult): EditorMode =
  ## Get the target mode for switching
  if cmdResult.kind == cmrModeSwitch:
    cmdResult.targetMode
  else:
    EditorMode.Normal # Default fallback

proc hasError*(cmdResult: CommandModeResult): bool =
  ## Check if there was an error
  cmdResult.kind == cmrError

proc getMessage*(cmdResult: CommandModeResult): string =
  ## Get message or error message
  case cmdResult.kind
  of cmrMessage: cmdResult.message
  of cmrError: cmdResult.errorMessage
  else: ""
