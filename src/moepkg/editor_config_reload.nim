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

import pkg/[results, celina]

import
  types/editor_types,
  editor_lsp,
  editor_init,
  git_cache,
  color,
  highlight,
  highlight_config,
  config_loader,
  sidebar,
  logger,
  registers,
  key_router,
  lsp_integration

proc applyConfigSettings*(e: Editor, newConfig: EditorConfig) =
  ## Apply configuration settings to the editor.
  ## Display/edit flags are pull-read from `e.config`, so the ref swap at the
  ## bottom of this proc is the only sync step they need. Other runtime state
  ## (search, timings, LSP, clipboard, notifications) still needs manual apply.

  if not newConfig.lsp.diagnostics.enable:
    # Diagnostics are server-push; drop applied markers/hover so a disable
    # takes effect visually too.
    e.clearAllDiagnostics()

  # Update search settings
  e.state.input.search.ignorecase = newConfig.standard.ignorecase
  e.state.input.search.smartcase = newConfig.standard.smartcase
  e.state.input.search.incsearch = newConfig.standard.incrementalSearch

  # Update timing intervals
  e.state.timing.gitDiffUpdateInterval = newConfig.git.updateInterval
  e.state.git.setGitDiffRefreshInterval(newConfig.git.updateInterval.int64)

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

  # Update reserved words and the highlight line-length cap on all buffers
  for buf in e.buffers:
    applyHighlightConfig(buf, newConfig)

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

  # Update mouse capture in the owning frontend.
  e.state.requestMouseCapture(newConfig.standard.mouse)

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

  # Store the new config; state.config aliases the same ref.
  e.config = newConfig
  e.state.config = newConfig

  # Re-apply [Lsp.<lang>] entries so live reload / :lspRestart pick up server
  # command/args/trace/rust-analyzer edits. Already-running workers keep
  # their old command until they restart (out of scope here).
  e.applyLspServerConfigs()

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

  # Config file was modified, reload it. Use loadConfig (not loadConfigFromToml)
  # so the dedicated keybindings.toml is re-merged too.
  logInfo("editor", "Config file modified, reloading: " & configPath)
  let loadResult = loadConfig()
  if loadResult.isErr:
    logError("editor", "Failed to reload config: " & loadResult.error)
    return

  let (newConfig, vr) = loadResult.get
  if vr.hasErrors:
    for msg in vr.toErrorMessages:
      logWarn("editor", "Config warning: " & msg)
  if vr.hasDeprecations:
    for msg in vr.toDeprecationMessages:
      logInfo("editor", "Config notice: " & msg)

  # Apply the new settings
  e.applyConfigSettings(newConfig)

  # Keybindings are declarative: the TOML config is authoritative, so reset the
  # user mapping layer and re-apply it (this drops session `:nmap` mappings).
  # Done here (file-change-triggered) rather than in applyConfigSettings, which
  # also runs on every keystroke in Config mode.
  var keyVr = newValidationResult()
  e.keyBindingRegistry.reapplyKeyMappings(newConfig.keyMapping, keyVr)
  for msg in keyVr.toErrorMessages:
    logWarn("editor", "KeyMapping reload: " & msg)

  # Command aliases/shell commands are declarative too: rebuild them from the
  # reloaded config (this drops session add/removeCommandAlias changes).
  e.commandConfig.applyCommandConfig(newConfig, e.commandLineParser)

  # Update last known modification time
  e.state.timing.lastConfigModTime = currentModTime

  e.state.statusMessage = "Configuration reloaded"
