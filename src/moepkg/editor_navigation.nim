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

## LSP navigation: definition / declaration / references / type-definition /
## implementation requests, and the jumps to the locations they return.

import std/[options, strutils, tables]

import pkg/results

import
  types/editor_types,
  editor_open,
  viewer_mode,
  editor_lsp,
  lsp_service,
  lsp_integration,
  references_viewer
import lsp/protocol/types as lspTypes

const
  LocationFeatures* =
    {lrfDefinition, lrfDeclaration, lrfReferences, lrfTypeDefinition, lrfImplementation}
  LocationValidModes* = {
    EditorMode.Normal, EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine
  }

func featureOfLocationKind*(kind: LspLocationRequestKind): LspRequestFeature =
  case kind
  of lrkDefinition: lrfDefinition
  of lrkDeclaration: lrfDeclaration
  of lrkReferences: lrfReferences
  of lrkTypeDefinition: lrfTypeDefinition
  of lrkImplementation: lrfImplementation
  of lrkNone: lrfDefinition
    # unreachable via startLspLocationRequest guards

func locationKindOfFeature*(f: LspRequestFeature): LspLocationRequestKind =
  case f
  of lrfDefinition: lrkDefinition
  of lrfDeclaration: lrkDeclaration
  of lrfReferences: lrkReferences
  of lrfTypeDefinition: lrkTypeDefinition
  of lrfImplementation: lrkImplementation
  else: lrkNone

func jumpPlacement(openWindow: bool): ViewerPlacement =
  if openWindow: vpVSplit else: vpInPlace

func lspTarget(line, utf16Column: int): Option[TargetPosition] =
  some(TargetPosition(line: line, column: utf16Column, unit: cuUtf16))

proc jumpToLspLocation*(
    e: Editor, loc: lspTypes.Location, resultKind: string, openWindow: bool = false
): bool =
  ## Jump to a single LSP location. When `openWindow` is true, the jump
  ## happens in a new vertical split window instead of the current one.
  ## Returns true if successful
  ##
  ## The URI is LSP-server-sourced: only a well-formed
  ## local file URI may open a buffer, so anything else is refused here.
  let pathRes = lsp_service.validateLocalFileUri(loc.uri)
  if pathRes.isErr:
    e.state.statusMessage = "Cannot jump to non-file location: " & pathRes.error
    return false
  let path = pathRes.get
  let jumped = e.jumpToFile(
    path,
    lspTarget(loc.range.start.line, loc.range.start.character),
    jumpPlacement(openWindow),
  )
  if jumped.isErr:
    e.state.statusMessage = jumped.error
    return false
  e.state.statusMessage =
    if jumped.get == ooOpened:
      resultKind & " in " & path
    else:
      resultKind & " at line " & $(e.activeWindow.cursor.line + 1)
  true

proc handleLspLocations*(
    e: Editor,
    locations: seq[lspTypes.Location],
    title: string,
    singularName: string,
    openWindow: bool = false,
): bool =
  ## Handle LSP location results (shared by definition and references).
  ## `openWindow` makes the jump open a new vertical split window: directly
  ## for a single location, or on item selection in the References viewer
  ## when there are multiple.
  ## Returns true if successful
  if locations.len == 0:
    e.state.statusMessage = "No " & title.toLowerAscii() & " found"
    return false

  if locations.len == 1:
    # Single location - jump directly
    return e.jumpToLspLocation(locations[0], singularName, openWindow)
  else:
    # Multiple locations - open References viewer mode. The URIs are
    # server-sourced, so only well-formed local file URIs become jumpable
    # items; anything else is dropped rather than opened on Enter.
    var items: seq[ReferenceItem] = @[]
    for loc in locations:
      let pathRes = lsp_service.validateLocalFileUri(loc.uri)
      if pathRes.isErr:
        continue
      items.add(
        ReferenceItem(
          path: pathRes.get,
          line: loc.range.start.line,
          column: loc.range.start.character,
          text: "",
        )
      )
    if items.len == 0:
      e.state.statusMessage = "No local file locations found"
      return false

    # Enter References mode
    let refState = newReferencesViewerState(items, title)
    refState.openWindowOnJump = openWindow
    let entered = e.enterViewerMode(
      EditorMode.References,
      ModeState(kind: mskReferences, references: refState),
      refState.createReferencesTextBuffer(),
      vpInPlace,
    )
    if entered.isErr:
      e.state.statusMessage =
        "Failed to open " & title.toLowerAscii() & ": " & entered.error
      return false
    e.state.statusMessage = $items.len & " " & title.toLowerAscii() & " found"
    return true

proc jumpToLspPosition*(
    e: Editor, path: string, line, utf16Column: int, openWindow: bool = false
): bool =
  ## Jump to an LSP position (a 0-based line and a UTF-16 offset) in `path`.
  ## When `openWindow` is true, the jump happens in a new vertical split window
  ## instead of the current one. Returns true if successful.
  let jumped =
    e.jumpToFile(path, lspTarget(line, utf16Column), jumpPlacement(openWindow))
  if jumped.isErr:
    e.state.statusMessage = jumped.error
    return false
  true

proc startLspLocationRequest(e: Editor, kind: LspLocationRequestKind): bool =
  ## Start an async LSP location request (definition, declaration, references, etc.)
  ## Returns true if request was started successfully
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  let kindName =
    case kind
    of lrkDefinition: "definition"
    of lrkDeclaration: "declaration"
    of lrkReferences: "references"
    of lrkTypeDefinition: "type definition"
    of lrkImplementation: "implementation"
    of lrkNone: ""

  let activeBuffer = e.activeBuffer()

  let featureEnabled =
    case kind
    of lrkDefinition:
      e.lspFeatureEnabled(activeBuffer, definition)
    of lrkDeclaration:
      e.lspFeatureEnabled(activeBuffer, declaration)
    of lrkReferences:
      e.lspFeatureEnabled(activeBuffer, references)
    of lrkTypeDefinition:
      e.lspFeatureEnabled(activeBuffer, typeDefinition)
    of lrkImplementation:
      e.lspFeatureEnabled(activeBuffer, implementation)
    of lrkNone:
      false
  if not featureEnabled:
    e.state.statusMessage = "LSP " & kindName & " is disabled"
    return false

  # Guard against unsupported servers so we report "not supported" immediately
  # instead of issuing a request that only fails after the response timeout.
  let supported =
    case kind
    of lrkDefinition:
      e.lsp.hasDefinitionSupport(activeBuffer)
    of lrkDeclaration:
      e.lsp.hasDeclarationSupport(activeBuffer)
    of lrkReferences:
      e.lsp.hasReferencesSupport(activeBuffer)
    of lrkTypeDefinition:
      e.lsp.hasTypeDefinitionSupport(activeBuffer)
    of lrkImplementation:
      e.lsp.hasImplementationSupport(activeBuffer)
    of lrkNone:
      false
  if not supported:
    e.state.statusMessage =
      "LSP " & kindName & " is not supported by the language server"
    return false

  # Only one location request in flight at a time: a new one supersedes any
  # of the five kinds already pending.
  for f in LocationFeatures:
    cancelIfPending(e, f)

  let line = e.activeWindow.cursor.line
  let col = e.activeWindow.cursor.column
  let feature = featureOfLocationKind(kind)

  let ctxRes = e.startContextualRequest(
    feature,
    proc(): Result[int, string] =
      case kind
      of lrkDefinition:
        e.lsp.startDefinitionRequest(activeBuffer, line, col)
      of lrkDeclaration:
        e.lsp.startDeclarationRequest(activeBuffer, line, col)
      of lrkReferences:
        e.lsp.startReferencesRequest(activeBuffer, line, col)
      of lrkTypeDefinition:
        e.lsp.startTypeDefinitionRequest(activeBuffer, line, col)
      of lrkImplementation:
        e.lsp.startImplementationRequest(activeBuffer, line, col)
      of lrkNone:
        err("invalid location kind"),
    validModes = LocationValidModes,
    # goto-* response is URI-anchored (handleLspLocations opens by path), so a
    # mid-flight buffer switch must not drop it.
    isItemDriven = true,
    trigger = lrtUserAction,
  )
  if ctxRes.isErr:
    e.state.statusMessage = "LSP " & kindName & " failed: " & ctxRes.error
    return false
  return true

proc pollLspLocationRequest*(e: Editor) =
  ## Poll for pending LSP location request response
  ## This should be called from the main event loop (tick function)
  e.pollOneShotLspResponse(LocationFeatures, "request"):
    if resultOpt.isSome:
      let kind = locationKindOfFeature(feature)
      let locations = parseLocationsResponse(resultOpt.get)
      let (pluralName, singularName) =
        case kind
        of lrkDefinition:
          ("Definitions", "Definition")
        of lrkDeclaration:
          ("Declarations", "Declaration")
        of lrkReferences:
          ("References", "Reference")
        of lrkTypeDefinition:
          ("Type Definitions", "Type Definition")
        of lrkImplementation:
          ("Implementations", "Implementation")
        of lrkNone:
          ("", "")
      let openWindow =
        case kind
        of lrkDefinition: e.config.lsp.definition.openWindow
        of lrkDeclaration: e.config.lsp.declaration.openWindow
        of lrkTypeDefinition: e.config.lsp.typeDefinition.openWindow
        of lrkImplementation: e.config.lsp.implementation.openWindow
        of lrkReferences, lrkNone: false
      discard e.handleLspLocations(locations, pluralName, singularName, openWindow)
    else:
      e.state.statusMessage = "No results found"

proc requestLspGotoDefinition*(e: Editor): bool =
  ## Request LSP goto definition at current cursor position (async)
  ## Returns true if request was started
  e.startLspLocationRequest(lrkDefinition)

proc requestLspGotoDeclaration*(e: Editor): bool =
  ## Request LSP goto declaration at current cursor position (async)
  ## Returns true if request was started
  e.startLspLocationRequest(lrkDeclaration)

proc requestLspReferences*(e: Editor): bool =
  ## Request LSP find references at current cursor position (async)
  ## Returns true if request was started
  e.startLspLocationRequest(lrkReferences)

proc requestLspTypeDefinition*(e: Editor): bool =
  ## Request LSP goto type definition at current cursor position (async)
  ## Returns true if request was started
  e.startLspLocationRequest(lrkTypeDefinition)

proc requestLspImplementation*(e: Editor): bool =
  ## Request LSP goto implementation at current cursor position (async)
  ## Returns true if request was started
  e.startLspLocationRequest(lrkImplementation)
