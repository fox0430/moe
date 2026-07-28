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

## Unified handler result type
##
## Pure data layer. Defines the HandlerResultKind enum and HandlerResult
## variant object returned by every mode dispatcher in handler_manager and
## mode_dispatchers, plus a few small accessor helpers. Has no dependency
## on dispatch logic so both the orchestrator and the per-mode dispatcher
## modules can import it freely.

import std/options

import ../[modes, setting_options]
import ../buffer/core
import ../lsp/protocol/types as lspTypes

type
  HandlerResultGroup* = enum
    ## Post-dispatch classification of a HandlerResult. The overlay wrapper
    ## and any other consumer that needs to route by category should read this
    ## instead of inspecting individual kinds.
    hrgAppExit ## App is quitting; skip further teardown.
    hrgHandledGeneric ## Generic Handled/Unhandled/Error; consult modeTransition.
    hrgExitToNormal ## One-shot Command-mode action; overlay exits to Normal.
    hrgExitToNewMode ## Kind proc already set the target mode; overlay just exits.
    hrgExitAndResync ## Overlay exits and the wrapper resyncs to the current mode.

  HandlerResultKind* = enum
    hrHandled # Command was handled successfully
    hrQuit # Application should quit
    hrCquit # Application should quit with non-zero exit code
    hrCloseWindow # Close current window
    hrGotoLine # Jump to specific line
    hrVSplit # Vertical split window
    hrHSplit # Horizontal split window
    hrNew # Create new empty buffer in horizontal split
    hrVnew # Create new empty buffer in vertical split
    hrEnew # Create new empty buffer
    hrEdit # Edit/open file in current window
    hrSetBoolOption # Set boolean option
    hrSetIntOption # Set integer option
    hrSetFloatOption # Set float option
    hrClearSearchHighlight # Clear search highlighting
    hrSave # Save file
    hrSaveAll # Save all modified buffers (:wa)
    hrSaveAndQuit # Save file and quit
    hrSaveAllAndQuit # Save all modified buffers and quit (:wqa, :xa)
    hrBufferNext # Switch to next buffer
    hrBufferPrev # Switch to previous buffer
    hrBufferFirst # Switch to first buffer
    hrBufferLast # Switch to last buffer
    hrBuffer # Switch to buffer by number or name
    hrJumpToBuffer # Jump to specific buffer and position (Ctrl-o/Ctrl-i)
    hrBufferDelete # Delete current buffer
    hrStripWhitespace # Remove trailing whitespace
    hrFilerOpenFile # Open file from filer
    hrFilerOpenFileVSplit # Open file from filer in vertical split
    hrFilerOpenFileHSplit # Open file from filer in horizontal split
    hrFilerDeleteFile # Delete file/directory from filer
    hrFilerShowInfo # Show file information
    hrFilerQuit # Close filer and return to previous mode
    hrEnterFiler # Enter filer mode with optional path
    hrLogViewerQuit # Close log viewer window
    hrLogViewerRefresh # Refresh log viewer content
    hrEnterLogViewer # Enter log viewer mode
    hrHelpViewerQuit # Close help viewer and return to previous mode
    hrEnterHelpViewer # Enter help viewer mode
    hrQuickRun # Run the current buffer
    hrBufferManagerSelectBuffer # Select and switch to a buffer
    hrBufferManagerDeleteBuffer # Delete a buffer
    hrBufferManagerQuit # Close buffer manager and return to previous mode
    hrEnterBufferManager # Enter buffer manager mode
    hrBookmarkManagerJump # Jump to selected bookmark
    hrBookmarkManagerDelete # Delete selected bookmark
    hrBookmarkManagerQuit # Close bookmark manager and return to previous mode
    hrEnterBookmarkManager # Enter bookmark manager mode
    hrBackupManagerRestore # Restore a backup file
    hrBackupManagerDelete # Delete a backup file
    hrBackupManagerOpenDiff # Open diff viewer for a backup
    hrBackupManagerRefresh # Refresh backup list
    hrBackupManagerQuit # Close backup manager and return to previous mode
    hrEnterBackupManager # Enter backup manager mode
    hrDiffViewerQuit # Close diff viewer and return to previous mode
    hrEnterDiffViewer # Enter diff viewer mode
    hrRecentFile # Enter recent file selection mode
    hrRecentFileOpenFile # Open file from recent file mode
    hrRecentFileQuit # Quit recent file mode
    hrNextWindow # Move to next window
    hrPrevWindow # Move to previous window
    hrIncreaseWindowHeight # Increase active window height
    hrDecreaseWindowHeight # Decrease active window height
    hrIncreaseWindowWidth # Increase active window width
    hrDecreaseWindowWidth # Decrease active window width
    hrEqualizeWindows # Equalize all window sizes
    hrSwapWindow # Swap active window with next
    hrLspGotoDefinition # Execute LSP goto definition
    hrLspGotoDeclaration # Execute LSP goto declaration
    hrLspFindReferences # Execute LSP find references
    hrLspDocumentSymbol # Execute LSP document symbol request
    hrLspCodeLensExecute # Execute CodeLens on current line
    hrLspCallHierarchyIncoming # Execute LSP incoming calls
    hrLspCallHierarchyOutgoing # Execute LSP outgoing calls
    hrLspTypeDefinition # Execute LSP goto type definition
    hrLspImplementation # Execute LSP goto implementation
    hrLspHover # Execute LSP hover
    hrLspRename # Execute LSP rename
    hrLspSelectionRange # Execute LSP selection range
    hrLspDocumentLink # Execute LSP document link
    hrShellCommand # Execute shell command
    hrBackground # Pause editor and show terminal (:bg)
    hrJumpList # Show jump list (:ju, :jump)
    hrChanges # Show change list (:changes)
    hrConflictNext # Jump to next git conflict block (:conflictnext)
    hrConflictPrev # Jump to previous git conflict block (:conflictprev)
    hrBuild # Build current buffer (:build)
    hrDebug # Open debug mode (:debug)
    hrDebugViewerQuit # Close debug viewer
    hrConfig # Open configuration mode (:conf)
    hrConfigQuit # Close config mode and return to previous mode
    hrConfigSaveConfig # Save configuration to file
    hrPutConfigFile # Write sample config file (:putConfigFile)
    hrMan # Show manual page (:man)
    hrTheme # Change color theme (:theme)
    hrLspLog # Open LSP log viewer (:lspLog)
    hrLspFormat # LSP document formatting (:lspFormat)
    hrLspRestart # Restart LSP server (:lspRestart)
    hrLspFold # LSP folding range (:lspFold)
    hrLspExecuteCommand # LSP execute command (:lspExeCommand)
    hrSubstitute # Search and replace (:s)
    hrDeleteLines # Delete lines (:d, :%d)
    hrReferencesQuit # Close references viewer and return to previous mode
    hrReferencesJumpTo # Jump to the selected reference
    hrEnterReferences # Enter references viewer mode
    hrDocumentSymbolQuit # Close document symbol viewer and return to previous mode
    hrDocumentSymbolJumpTo # Jump to the selected symbol
    hrEnterDocumentSymbol # Enter document symbol viewer mode
    hrCallHierarchyQuit # Close call hierarchy viewer and return to previous mode
    hrCallHierarchyJumpTo # Jump to the selected call hierarchy item
    hrCallHierarchyRequestIncoming # Request incoming calls for selected item
    hrCallHierarchyRequestOutgoing # Request outgoing calls for selected item
    hrEnterCallHierarchy # Enter call hierarchy viewer mode
    hrEnterTerminal # Enter terminal mode
    hrTerminalQuit # Close terminal and return to previous mode
    hrExecCommand # Execute a Command mode command directly (@:)
    hrOnlyWindow # Close all other windows (:only)
    hrEnterFileTree # Enter/toggle fileTree sidebar
    hrFileTreeOpenFile # Open file from fileTree
    hrFileTreeQuit # Close fileTree sidebar
    hrOpenUri # Open URI/file under cursor
    hrPlaybackMacro # Playback a recorded macro (@a, N@a) via nested playback loop
    hrUnhandled # Command was not handled
    hrError # Error occurred
    hrMapAdd # Add runtime key mapping (:map, :nmap, etc.)
    hrMapRemove # Remove runtime key mapping (:unmap, :nunmap, etc.)
    hrMapClear # Clear runtime key mappings (:mapclear, :nmapclear, etc.)
    hrMapList # List runtime key mappings

  HandlerResult* = object ## Unified result type for all handlers
    case kind*: HandlerResultKind
    of hrHandled:
      modeTransition*: Option[EditorMode]
      overlayTransition*: Option[OverlayKind]
      statusMessage*: string
    of hrQuit, hrCquit:
      discard
    of hrCloseWindow:
      forceClose*: bool
    of hrGotoLine:
      lineNumber*: int
    of hrVSplit:
      vsplitFilename*: Option[string]
    of hrHSplit:
      hsplitFilename*: Option[string]
    of hrNew:
      discard
    of hrVnew:
      discard
    of hrEnew:
      discard
    of hrEdit:
      editFilename*: Option[string]
      forceEdit*: bool
    of hrSetBoolOption:
      boolOption*: BoolSettingOption
      boolValue*: bool
    of hrSetIntOption:
      intOption*: IntSettingOption
      intValue*: int
    of hrSetFloatOption:
      floatOption*: FloatSettingOption
      floatValue*: float
    of hrClearSearchHighlight:
      discard
    of hrSave:
      saveFilename*: Option[string]
      forceSave*: bool
    of hrSaveAll:
      forceSaveAll*: bool
    of hrSaveAndQuit:
      saveAndQuitFilename*: Option[string]
      forceQuitAfterSave*: bool
    of hrSaveAllAndQuit:
      forceSaveAllAndQuitAfter*: bool
    of hrBufferNext, hrBufferPrev, hrBufferFirst, hrBufferLast:
      discard
    of hrBuffer:
      bufferArg*: string # Buffer number or name
    of hrJumpToBuffer:
      jumpBufferId*: BufferId # Target BufferId
      jumpLine*: int # Target line number
      jumpColumn*: int # Target column number
    of hrBufferDelete:
      forceBufferDelete*: bool
    of hrStripWhitespace:
      strippedLineCount*: int
    of hrFilerOpenFile, hrFilerOpenFileVSplit, hrFilerOpenFileHSplit:
      filerFilePath*: string
    of hrFilerDeleteFile:
      filerDeletePath*: string
    of hrFilerShowInfo:
      filerFileInfo*: string
    of hrFilerQuit:
      discard
    of hrEnterFiler:
      enterFilerPath*: Option[string]
    of hrLogViewerQuit:
      discard
    of hrLogViewerRefresh:
      discard
    of hrEnterLogViewer:
      discard
    of hrHelpViewerQuit:
      discard
    of hrEnterHelpViewer:
      discard
    of hrQuickRun:
      discard
    of hrBufferManagerSelectBuffer:
      selectBufferIndex*: int
    of hrBufferManagerDeleteBuffer:
      deleteBufferIdx*: int
    of hrBufferManagerQuit:
      discard
    of hrEnterBufferManager:
      discard
    of hrBookmarkManagerJump:
      bookmarkJumpBufferId*: BufferId
      bookmarkJumpLine*: int
    of hrBookmarkManagerDelete:
      bookmarkDeleteEntryIndex*: int
    of hrBookmarkManagerQuit:
      discard
    of hrEnterBookmarkManager:
      discard
    of hrBackupManagerRestore:
      restoreBackupIndex*: int
    of hrBackupManagerDelete:
      deleteBackupIndex*: int
    of hrBackupManagerOpenDiff:
      diffBackupIndex*: int
    of hrBackupManagerRefresh:
      discard
    of hrBackupManagerQuit:
      discard
    of hrEnterBackupManager:
      discard
    of hrDiffViewerQuit:
      discard
    of hrEnterDiffViewer:
      diffSourcePath*: string
      diffBackupPath*: string
    of hrRecentFile:
      discard
    of hrRecentFileOpenFile:
      recentFilePath*: string
    of hrRecentFileQuit:
      discard
    of hrNextWindow, hrPrevWindow:
      discard
    of hrIncreaseWindowHeight, hrDecreaseWindowHeight, hrIncreaseWindowWidth,
        hrDecreaseWindowWidth, hrEqualizeWindows, hrSwapWindow:
      discard
    of hrLspGotoDefinition:
      discard
    of hrLspGotoDeclaration:
      discard
    of hrLspFindReferences:
      discard
    of hrLspDocumentSymbol:
      discard
    of hrLspCodeLensExecute:
      discard
    of hrLspCallHierarchyIncoming:
      discard
    of hrLspCallHierarchyOutgoing:
      discard
    of hrLspTypeDefinition:
      discard
    of hrLspImplementation:
      discard
    of hrLspHover:
      discard
    of hrLspRename:
      hrLspNewName*: string
    of hrLspSelectionRange:
      discard
    of hrLspDocumentLink:
      discard
    of hrShellCommand:
      shellCommand*: string
    of hrBackground:
      discard
    of hrJumpList:
      discard
    of hrChanges:
      discard
    of hrConflictNext:
      discard
    of hrConflictPrev:
      discard
    of hrBuild:
      discard
    of hrDebug:
      discard
    of hrDebugViewerQuit:
      discard
    of hrConfig:
      discard
    of hrConfigQuit:
      discard
    of hrConfigSaveConfig:
      discard
    of hrPutConfigFile:
      discard
    of hrMan:
      hrManPage*: string
    of hrTheme:
      hrThemeName*: string
    of hrLspLog:
      discard
    of hrLspFormat:
      discard
    of hrLspRestart:
      discard
    of hrLspFold:
      discard
    of hrLspExecuteCommand:
      hrLspCommand*: string
      hrLspCommandArgs*: seq[string]
    of hrSubstitute:
      hrSubstituteCount*: int
    of hrDeleteLines:
      hrDeletedText*: string
      hrDeletedLineCount*: int
    of hrReferencesQuit:
      discard
    of hrReferencesJumpTo:
      jumpToPath*: string
      jumpToLine*: int
      jumpToColumn*: int
    of hrEnterReferences:
      discard
    of hrDocumentSymbolQuit:
      discard
    of hrDocumentSymbolJumpTo:
      symbolLine*: int
      symbolColumn*: int
    of hrEnterDocumentSymbol:
      discard
    of hrCallHierarchyQuit:
      discard
    of hrCallHierarchyJumpTo:
      callHierarchyJumpUri*: string
      callHierarchyJumpLine*: int
      callHierarchyJumpColumn*: int
    of hrCallHierarchyRequestIncoming:
      callHierarchyIncomingItem*: lspTypes.CallHierarchyItem
    of hrCallHierarchyRequestOutgoing:
      callHierarchyOutgoingItem*: lspTypes.CallHierarchyItem
    of hrEnterCallHierarchy:
      discard
    of hrEnterTerminal:
      enterTerminalCommand*: string # Optional command (empty = default shell)
    of hrTerminalQuit:
      discard
    of hrExecCommand:
      execCommandText*: string # Command text (without leading ":")
      execCommandCount*: int # Number of times to execute
    of hrOnlyWindow:
      discard
    of hrEnterFileTree:
      enterFileTreePath*: Option[string]
    of hrFileTreeOpenFile:
      fileTreeFilePath*: string
    of hrFileTreeQuit:
      discard
    of hrOpenUri:
      openUri*: string
    of hrPlaybackMacro:
      playbackMacroKeys*: seq[string]
      playbackMacroCount*: int
    of hrMapAdd:
      mapAddLhs*: string
      mapAddRhs*: string
      mapAddModes*: seq[EditorMode]
      mapAddNoremap*: bool
    of hrMapRemove:
      mapRemoveLhs*: string
      mapRemoveModes*: seq[EditorMode]
    of hrMapClear:
      mapClearModes*: seq[EditorMode]
    of hrMapList:
      mapListModes*: seq[EditorMode]
      mapListPrefix*: string
    of hrUnhandled:
      discard
    of hrError:
      errorMessage*: string

# Utility functions for HandlerResult
proc hasError*(hrResult: HandlerResult): bool =
  ## Check if there was an error
  hrResult.kind == hrError

proc getModeTransition*(hrResult: HandlerResult): Option[EditorMode] =
  ## Get mode transition if any
  if hrResult.kind == hrHandled:
    hrResult.modeTransition
  else:
    none(EditorMode)

proc getOverlayTransition*(hrResult: HandlerResult): Option[OverlayKind] =
  ## Get overlay transition if any
  if hrResult.kind == hrHandled:
    hrResult.overlayTransition
  else:
    none(OverlayKind)

proc getStatusMessage*(hrResult: HandlerResult): string =
  ## Get status message if any
  case hrResult.kind
  of hrHandled: hrResult.statusMessage
  of hrError: hrResult.errorMessage
  else: ""

proc group*(k: HandlerResultKind): HandlerResultGroup =
  ## Category of `k` for post-dispatch routing. Exhaustive over
  ## `HandlerResultKind`, so a newly added kind fails to compile here until it
  ## is classified.
  case k
  of hrQuit, hrCquit:
    hrgAppExit
  of hrHandled, hrUnhandled, hrError:
    hrgHandledGeneric
  of hrQuickRun, hrBuild, hrSubstitute, hrDeleteLines, hrJumpList, hrChanges,
      hrConflictNext, hrConflictPrev, hrTheme, hrPutConfigFile, hrLspFormat,
      hrLspRestart, hrLspFold, hrLspExecuteCommand, hrLspCallHierarchyIncoming,
      hrLspCallHierarchyOutgoing:
    hrgExitToNormal
  of hrEnterFiler, hrEnterTerminal, hrEnterLogViewer, hrLspLog, hrEnterHelpViewer,
      hrEnterBufferManager, hrEnterBackupManager, hrRecentFile, hrDebug,
      hrEnterBookmarkManager, hrConfig:
    hrgExitToNewMode
  of hrCloseWindow, hrGotoLine, hrVSplit, hrHSplit, hrEnew, hrNew, hrVnew, hrEdit,
      hrSetBoolOption, hrSetIntOption, hrSetFloatOption, hrClearSearchHighlight,
      hrShellCommand, hrMan, hrBackground, hrSave, hrSaveAll, hrSaveAndQuit,
      hrSaveAllAndQuit, hrBufferNext, hrBufferPrev, hrBufferFirst, hrBufferLast,
      hrBuffer, hrBufferDelete, hrStripWhitespace, hrOnlyWindow, hrEnterFileTree,
      hrJumpToBuffer, hrFilerOpenFile, hrFilerOpenFileVSplit, hrFilerOpenFileHSplit,
      hrFilerDeleteFile, hrFilerShowInfo, hrFilerQuit, hrLogViewerRefresh,
      hrHelpViewerQuit, hrReferencesQuit, hrReferencesJumpTo, hrEnterReferences,
      hrDocumentSymbolQuit, hrDocumentSymbolJumpTo, hrEnterDocumentSymbol,
      hrCallHierarchyQuit, hrCallHierarchyJumpTo, hrCallHierarchyRequestIncoming,
      hrCallHierarchyRequestOutgoing, hrEnterCallHierarchy, hrBufferManagerSelectBuffer,
      hrBufferManagerDeleteBuffer, hrBufferManagerQuit, hrBookmarkManagerJump,
      hrBookmarkManagerDelete, hrBookmarkManagerQuit, hrBackupManagerRestore,
      hrBackupManagerDelete, hrBackupManagerOpenDiff, hrBackupManagerRefresh,
      hrBackupManagerQuit, hrDiffViewerQuit, hrEnterDiffViewer, hrRecentFileOpenFile,
      hrRecentFileQuit, hrNextWindow, hrPrevWindow, hrIncreaseWindowHeight,
      hrDecreaseWindowHeight, hrIncreaseWindowWidth, hrDecreaseWindowWidth,
      hrEqualizeWindows, hrSwapWindow, hrLspGotoDefinition, hrLspGotoDeclaration,
      hrLspFindReferences, hrLspDocumentSymbol, hrLspCodeLensExecute,
      hrLspTypeDefinition, hrLspImplementation, hrLspHover, hrLspRename,
      hrLspSelectionRange, hrLspDocumentLink, hrConfigQuit, hrConfigSaveConfig,
      hrDebugViewerQuit, hrLogViewerQuit, hrTerminalQuit, hrExecCommand,
      hrFileTreeOpenFile, hrFileTreeQuit, hrOpenUri, hrPlaybackMacro, hrMapAdd,
      hrMapRemove, hrMapClear, hrMapList:
    hrgExitAndResync

proc group*(r: HandlerResult): HandlerResultGroup =
  ## `r`'s category. Same values as `group(kind)`; supplied so consumers
  ## already holding a HandlerResult don't need to reach into `.kind`.
  r.kind.group
