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

## Live config reload: apply a freshly loaded `EditorConfig` to the running
## editor (display, search, color, LSP, theme, mouse, notification, key-router
## settings) and poll the config file for external changes.

import std/[monotimes, times, os]

import pkg/results

import
  types/editor_types,
  editor_lsp,
  status_line,
  color,
  highlight,
  config_loader,
  sidebar,
  logger,
  registers

proc applyConfigSettings*(e: Editor, newConfig: EditorConfig) =
  ## Apply configuration settings to the editor
  ## Updates display settings, search settings, and other runtime state
  ## Note: Some settings require editor restart to take effect

  # Update display settings from config
  e.state.display.showTabLine = newConfig.tabLine.enable
  e.state.display.showStatusLine = newConfig.standard.statusLine
  e.state.display.multiStatusLine = newConfig.statusLine.multipleStatusLine
  e.state.display.showLineNumbers = newConfig.standard.number
  e.state.display.relativeLineNumbers = newConfig.standard.relativeNumber
  e.state.display.showCursorLine = newConfig.highlight.currentLine
  e.state.display.showCursorColumn = newConfig.highlight.currentColumn
  e.state.display.showSyntax = newConfig.standard.syntax
  e.state.display.showIndentationLines = newConfig.standard.indentationLines
  e.state.display.showSidebar = newConfig.standard.sidebar
  e.state.display.scrollbar = newConfig.standard.scrollbar
  e.state.display.scrollbarWidth = newConfig.standard.scrollbarWidth
  e.state.display.showModifiedLines = newConfig.standard.showModifiedLines
  e.state.display.showGitDiff = newConfig.git.showChangedLine
  e.state.display.showSyntaxChecker = newConfig.syntaxChecker.enable
  e.state.display.showCodeLens = newConfig.lsp.codeLens.enable
  e.state.display.showDocumentHighlight = newConfig.lsp.documentHighlight.enable
  e.state.display.showInlayHint = newConfig.lsp.inlayHint.enable

  # The insert handler caches lsp.completion.enable and autocomplete.enable as
  # flags (it has no access to e.config), so re-sync them on reload like the
  # display flags above.
  e.handlerManager.insertHandler.lspCompletionEnabled = newConfig.lsp.completion.enable
  e.handlerManager.insertHandler.autocompleteEnabled = newConfig.autocomplete.enable

  if not newConfig.lsp.diagnostics.enable:
    # Diagnostics are server-push; when disabled, incoming publishDiagnostics are
    # dropped in applyDiagnosticsForUri. Clear what was already applied so
    # existing markers and hover content disappear on reload too.
    e.clearAllDiagnostics()

  e.state.display.tabStop = newConfig.standard.tabStop
  e.state.display.shiftWidth = newConfig.standard.shiftWidth
  e.state.display.softTabStop = newConfig.standard.softTabStop
  e.state.display.expandTab = newConfig.standard.expandTab
  e.state.display.autoIndent = newConfig.standard.autoIndent
  e.state.display.smartIndent = newConfig.standard.smartIndent
  e.state.display.autoCloseParen = newConfig.standard.autoCloseParen
  e.state.display.autoDeleteParen = newConfig.standard.autoDeleteParen
  e.state.display.bracketSplit = newConfig.standard.bracketSplit

  # Update search settings
  e.state.input.search.ignorecase = newConfig.standard.ignorecase
  e.state.input.search.smartcase = newConfig.standard.smartcase
  e.state.input.search.incsearch = newConfig.standard.incrementalSearch

  # Update timing intervals
  e.state.timing.gitDiffUpdateInterval = newConfig.git.updateInterval
  setGitDiffRefreshInterval(newConfig.git.updateInterval.int64)

  # Update color mode with fallback
  let requestedColorMode =
    case newConfig.standard.colorMode
    of cm8color: cmk8color
    of cm16color: cmk16color
    of cm256color: cmk256color
    of cm24bit: cmk24bit
    of cmNone: cmkNone
  globalColorMode = applyColorModeFallback(requestedColorMode)

  # Update clipboard tool if enabled
  if newConfig.clipboard.enable:
    e.state.registers.setClipboardTool(newConfig.clipboard.tool)

  # Update reserved words on all buffers
  let reservedWords = toReservedWords(newConfig.highlight.reservedWord)
  for buf in e.buffers:
    buf.setReservedWords(reservedWords)

  # Reload theme if configured
  initTheme(newConfig)

  # Update sidebar bookmark marker
  setBookmarkMarker(newConfig.standard.bookmarkMarker)

  # Update LSP enable/disable. On a runtime enabled->disabled transition, shut
  # the servers down rather than leaving them running: poll() is gated on
  # `enabled`, so a still-running server could otherwise block forever on a
  # server-initiated request (e.g. workspace/applyEdit) whose event would never
  # be drained or answered.
  let lspWasEnabled = e.lsp.enabled
  e.lsp.setEnabled(newConfig.lsp.enable)
  if lspWasEnabled and not newConfig.lsp.enable:
    e.lsp.shutdown()
  e.lsp.service.setRequestTimeout(newConfig.lsp.timeout)

  # Update mouse capture
  if not e.app.isNil:
    if newConfig.standard.mouse:
      e.app.enableMouse()
    else:
      e.app.disableMouse()

  # Update notification popup settings
  e.state.notificationPopup.timeoutMs = newConfig.notification.popupTimeoutMs
  e.state.notificationPopup.maxVisible = newConfig.notification.popupMaxVisible
  e.state.notificationPopup.maxWidth = newConfig.notification.popupMaxWidth
  e.state.notificationPopup.showBorder = newConfig.notification.popupBorder
  case newConfig.notification.popupPosition
  of "topRight":
    e.state.notificationPopup.position = nppTopRight
  of "topLeft":
    e.state.notificationPopup.position = nppTopLeft
  of "bottomLeft":
    e.state.notificationPopup.position = nppBottomLeft
  else:
    e.state.notificationPopup.position = nppBottomRight

  # Propagate timeout policy to the key router so live reload and
  # config-mode edits take effect for runtime-mapping timeouts.
  e.keyRouter.updatePolicy(
    TimeoutPolicy(timeoutlen: newConfig.standard.timeoutlen, enabled: true)
  )

  # Store the new config
  e.config = newConfig

proc maybeReloadConfig*(e: Editor) =
  ## Check if config file was modified and reload if:
  ##   - liveReloadOfConf is enabled in config
  ##   - Enough time has passed since last check (debouncing)
  ##   - Config file modification time has changed

  if not e.config.standard.liveReloadOfConf:
    return

  let now = getMonoTime()
  let elapsed = now - e.state.timing.lastConfigCheck
  let threshold = initDuration(milliseconds = e.state.timing.configCheckInterval)

  if elapsed < threshold:
    return

  e.state.timing.lastConfigCheck = now

  # Check if config file exists and has been modified
  let configPath = getConfigPath()
  if not fileExists(configPath):
    return

  var currentModTime: times.Time
  try:
    currentModTime = getFileInfo(configPath).lastWriteTime
  except OSError:
    return

  # Compare modification times
  if currentModTime == e.state.timing.lastConfigModTime:
    return

  # Config file was modified, reload it
  logInfo("editor", "Config file modified, reloading: " & configPath)
  let loadResult = loadConfigFromToml(configPath)
  if loadResult.isErr:
    logError("editor", "Failed to reload config: " & loadResult.error)
    return

  let (newConfig, vr) = loadResult.get
  if vr.hasErrors:
    for msg in vr.toErrorMessages:
      logWarn("editor", "Config warning: " & msg)

  # Apply the new settings
  e.applyConfigSettings(newConfig)

  # Update last known modification time
  e.state.timing.lastConfigModTime = currentModTime

  e.state.statusMessage = "Configuration reloaded"
