#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import std/[options, strutils]

import pkg/results

import ../[buffer, modes, commandline, commandconfig, commandregistry]

type
  CommandModeResultKind* = enum
    cmrQuit # Application should quit
    cmrCloseWindow # Close current window
    cmrModeSwitch # Switch to different mode
    cmrMessage # Show status message
    cmrGotoLine # Jump to specific line
    cmrVSplit # Vertical split window
    cmrHSplit # Horizontal split window
    cmrSetMultiStatusLine # Set multi status line
    cmrSetIgnoreCase # Set ignorecase option
    cmrSetSmartCase # Set smartcase option
    cmrSetIncSearch # Set incsearch option
    cmrSetHlSearch # Set hlsearch option
    cmrSave # Save file
    cmrSaveAndQuit # Save file and quit
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
    of cmrSetMultiStatusLine:
      enabled*: bool
    of cmrSetIgnoreCase:
      ignorecaseEnabled*: bool
    of cmrSetSmartCase:
      smartcaseEnabled*: bool
    of cmrSetIncSearch:
      incsearchEnabled*: bool
    of cmrSetHlSearch:
      hlsearchEnabled*: bool
    of cmrSave:
      saveFilename*: Option[string]
    of cmrSaveAndQuit:
      saveAndQuitFilename*: Option[string]
      forceSaveAndQuit*: bool
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
  return CommandModeResult(kind: cmrSave, saveFilename: filename)

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
  # TODO: Implement file loading
  return CommandModeResult(kind: cmrMessage, message: "Opened: " & filename)

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
  case option.toLower
  of "multistatusline":
    return CommandModeResult(kind: cmrSetMultiStatusLine, enabled: true)
  of "nomultistatusline":
    return CommandModeResult(kind: cmrSetMultiStatusLine, enabled: false)
  of "ignorecase", "ic":
    return CommandModeResult(kind: cmrSetIgnoreCase, ignorecaseEnabled: true)
  of "noignorecase", "noic":
    return CommandModeResult(kind: cmrSetIgnoreCase, ignorecaseEnabled: false)
  of "smartcase", "scs":
    return CommandModeResult(kind: cmrSetSmartCase, smartcaseEnabled: true)
  of "nosmartcase", "noscs":
    return CommandModeResult(kind: cmrSetSmartCase, smartcaseEnabled: false)
  of "incsearch", "is":
    return CommandModeResult(kind: cmrSetIncSearch, incsearchEnabled: true)
  of "noincsearch", "nois":
    return CommandModeResult(kind: cmrSetIncSearch, incsearchEnabled: false)
  of "hlsearch", "hls":
    return CommandModeResult(kind: cmrSetHlSearch, hlsearchEnabled: true)
  of "nohlsearch", "nohls":
    return CommandModeResult(kind: cmrSetHlSearch, hlsearchEnabled: false)
  else:
    # TODO: Implement other settings management
    let optionStr =
      if value.isSome:
        option & "=" & value.get
      else:
        option

    return CommandModeResult(kind: cmrMessage, message: "Set: " & optionStr)

proc executeHelp*(
    handler: CommandModeHandler, topic: Option[string]
): CommandModeResult =
  ## Execute help command (:help, :help topic)
  let helpTopic = if topic.isSome: topic.get else: "general"

  return CommandModeResult(kind: cmrMessage, message: "Help for: " & helpTopic)

proc executeVSplit*(
    handler: CommandModeHandler, filename: Option[string]
): CommandModeResult =
  ## Execute vertical split command (:vs, :vs filename)
  return CommandModeResult(kind: cmrVSplit, vsplitFilename: filename)

proc executeHSplit*(
    handler: CommandModeHandler, filename: Option[string]
): CommandModeResult =
  ## Execute horizontal split command (:sp, :sp filename)
  return CommandModeResult(kind: cmrHSplit, hsplitFilename: filename)

proc handleCommandModeInput*(
    handler: CommandModeHandler,
    buffer: TextBuffer,
    commandText: string,
    isSharedBuffer: bool = false,
): CommandModeResult =
  ## Main entry point for handling Command mode input
  ## isSharedBuffer: true if the buffer is shared across multiple windows

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
    return handler.executeSave(buffer, cmdResult.filename, false)
  of claSaveAll:
    # TODO: Handle save all (multiple buffers)
    return handler.executeSave(buffer, none(string), cmdResult.forceSaveAll)
  of claSaveAndQuit:
    return handler.executeSaveAndQuit(buffer, cmdResult.saveFilename, false)
  of claSaveAllAndQuit:
    # TODO: Handle save all and quit
    return
      handler.executeSaveAndQuit(buffer, none(string), cmdResult.forceSaveAllAndQuit)
  of claEdit:
    return handler.executeEdit(buffer, cmdResult.editFilename)
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
  of claSubstitute:
    # TODO: Implement search and replace
    return CommandModeResult(kind: cmrMessage, message: "Substitute not implemented")
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
