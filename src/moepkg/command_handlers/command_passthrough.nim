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

## Passthrough commandId dispatch table
##
## Single source of truth for commandIds that translate 1:1 into a
## HandlerResult without needing editor/buffer state. Used by:
##   * normal_handler.nim — Normal mode ctAction / ctCustom branches
##   * handler_manager.nim:executeCommandDirect — Special mode runtime mapping
##   * handler_manager.nim:handleNormalMode — Normal mode result translation
##
## Stateful commandIds (changelist.*, bookmark.*, jump.*, macro.record,
## editor.open.uri, insert.*, edit.{undo,redo}) are NOT handled here and remain
## in normal_handler.nim with full editor context.

import std/options

import ./handler_result

type PassthroughKind* = enum
  # window.*
  ptNextWindow
  ptPrevWindow
  ptIncreaseWindowHeight
  ptDecreaseWindowHeight
  ptIncreaseWindowWidth
  ptDecreaseWindowWidth
  ptEqualizeWindows
  ptSwapWindow
  ptCloseWindow
  # file.*
  ptSave
  ptSaveAndQuit
  ptQuitForce
  ptBufferDelete
  ptNewFile
  ptEnterFiler
  # buffer.*
  ptBufferNext
  ptBufferPrev
  # quickrun
  ptQuickRun
  # lsp.* (ctCustom)
  ptLspGotoDefinition
  ptLspGotoDeclaration
  ptLspFindReferences
  ptLspCodeLensExecute
  ptLspCallHierarchyIncoming
  ptLspCallHierarchyOutgoing
  ptLspTypeDefinition
  ptLspImplementation
  ptLspHover
  ptLspRename
  ptLspSelectionRange
  ptLspDocumentLink
  ptLspDocumentSymbol

proc lookupPassthrough*(commandId: string): Option[PassthroughKind] =
  ## Return the canonical PassthroughKind for `commandId`, or none for
  ## commandIds that need editor state (handled elsewhere).
  case commandId
  of "window.next":
    some(ptNextWindow)
  of "window.prev":
    some(ptPrevWindow)
  of "window.increase-height":
    some(ptIncreaseWindowHeight)
  of "window.decrease-height":
    some(ptDecreaseWindowHeight)
  of "window.increase-width":
    some(ptIncreaseWindowWidth)
  of "window.decrease-width":
    some(ptDecreaseWindowWidth)
  of "window.equalize":
    some(ptEqualizeWindows)
  of "window.swap":
    some(ptSwapWindow)
  of "window.close":
    some(ptCloseWindow)
  of "file.save":
    some(ptSave)
  of "file.save.and.quit":
    some(ptSaveAndQuit)
  of "file.quit.force":
    some(ptQuitForce)
  of "file.close":
    some(ptBufferDelete)
  of "file.new":
    some(ptNewFile)
  of "file.open", "filer.open":
    some(ptEnterFiler)
  of "buffer.next.tab":
    some(ptBufferNext)
  of "buffer.prev.tab":
    some(ptBufferPrev)
  of "quickrun":
    some(ptQuickRun)
  of "lsp.goto.definition":
    some(ptLspGotoDefinition)
  of "lsp.goto.declaration":
    some(ptLspGotoDeclaration)
  of "lsp.find.references":
    some(ptLspFindReferences)
  of "lsp.codelens.execute":
    some(ptLspCodeLensExecute)
  of "lsp.callhierarchy.incoming":
    some(ptLspCallHierarchyIncoming)
  of "lsp.callhierarchy.outgoing":
    some(ptLspCallHierarchyOutgoing)
  of "lsp.goto.type.definition":
    some(ptLspTypeDefinition)
  of "lsp.goto.implementation":
    some(ptLspImplementation)
  of "lsp.hover":
    some(ptLspHover)
  of "lsp.rename":
    some(ptLspRename)
  of "lsp.selection.range":
    some(ptLspSelectionRange)
  of "lsp.document.link":
    some(ptLspDocumentLink)
  of "lsp.document.symbol":
    some(ptLspDocumentSymbol)
  else:
    none(PassthroughKind)

proc toHandlerResult*(k: PassthroughKind): HandlerResult =
  ## Translate a PassthroughKind into its canonical HandlerResult.
  case k
  of ptNextWindow:
    HandlerResult(kind: hrNextWindow)
  of ptPrevWindow:
    HandlerResult(kind: hrPrevWindow)
  of ptIncreaseWindowHeight:
    HandlerResult(kind: hrIncreaseWindowHeight)
  of ptDecreaseWindowHeight:
    HandlerResult(kind: hrDecreaseWindowHeight)
  of ptIncreaseWindowWidth:
    HandlerResult(kind: hrIncreaseWindowWidth)
  of ptDecreaseWindowWidth:
    HandlerResult(kind: hrDecreaseWindowWidth)
  of ptEqualizeWindows:
    HandlerResult(kind: hrEqualizeWindows)
  of ptSwapWindow:
    HandlerResult(kind: hrSwapWindow)
  of ptCloseWindow:
    HandlerResult(kind: hrCloseWindow, forceClose: false)
  of ptSave:
    HandlerResult(kind: hrSave, saveFilename: none(string), forceSave: false)
  of ptSaveAndQuit:
    HandlerResult(
      kind: hrSaveAndQuit, saveAndQuitFilename: none(string), forceQuitAfterSave: false
    )
  of ptQuitForce:
    HandlerResult(kind: hrQuit)
  of ptBufferDelete:
    HandlerResult(kind: hrBufferDelete, forceBufferDelete: false)
  of ptNewFile:
    HandlerResult(kind: hrEnew)
  of ptEnterFiler:
    HandlerResult(kind: hrEnterFiler, enterFilerPath: none(string))
  of ptBufferNext:
    HandlerResult(kind: hrBufferNext)
  of ptBufferPrev:
    HandlerResult(kind: hrBufferPrev)
  of ptQuickRun:
    HandlerResult(kind: hrQuickRun)
  of ptLspGotoDefinition:
    HandlerResult(kind: hrLspGotoDefinition)
  of ptLspGotoDeclaration:
    HandlerResult(kind: hrLspGotoDeclaration)
  of ptLspFindReferences:
    HandlerResult(kind: hrLspFindReferences)
  of ptLspCodeLensExecute:
    HandlerResult(kind: hrLspCodeLensExecute)
  of ptLspCallHierarchyIncoming:
    HandlerResult(kind: hrLspCallHierarchyIncoming)
  of ptLspCallHierarchyOutgoing:
    HandlerResult(kind: hrLspCallHierarchyOutgoing)
  of ptLspTypeDefinition:
    HandlerResult(kind: hrLspTypeDefinition)
  of ptLspImplementation:
    HandlerResult(kind: hrLspImplementation)
  of ptLspHover:
    HandlerResult(kind: hrLspHover)
  of ptLspRename:
    HandlerResult(kind: hrLspRename, hrLspNewName: "")
  of ptLspSelectionRange:
    HandlerResult(kind: hrLspSelectionRange)
  of ptLspDocumentLink:
    HandlerResult(kind: hrLspDocumentLink)
  of ptLspDocumentSymbol:
    HandlerResult(kind: hrLspDocumentSymbol)
