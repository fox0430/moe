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

## Config mode side effects (entry, exit, save, putConfigFile), split
## out of result_processor.nim.

import std/os

import pkg/results

import ../[config_loader, config_mode, editor, logger, types, viewer_mode]

import handler_result

proc processConfigResult*(e: Editor, r: HandlerResult): bool =
  ## Handle hrConfig* kinds (entry/exit, save, putConfigFile).
  ## Returns true to continue.
  case r.kind
  of hrConfig:
    if e.focusExistingViewerWindow(EditorMode.Config):
      return true
    let configBuffer = newTextBuffer("")
    configBuffer.readOnly = true
    let enterResult = e.enterViewerMode(
      EditorMode.Config,
      ModeState(kind: mskConfig, config: newConfigModeState(e.config)),
      configBuffer,
      vpVSplit,
    )
    if enterResult.isErr:
      e.state.statusMessage = "Failed to open config: " & enterResult.error
    return true
  of hrConfigQuit:
    # Close config mode and return to previous mode
    let activeWin = e.activeWindow
    # Flush pending apply before exiting; the outer pendingApply check runs
    # after processResult and would otherwise lose the change.
    if activeWin.modeState.kind == mskConfig and activeWin.modeState.config.pendingApply:
      e.applyConfigSettings(e.config)
    e.leaveViewerMode(EditorMode.Config)
    return true
  of hrConfigSaveConfig:
    # Save configuration to TOML file
    let configPath = getConfigPath()

    # Backup existing config file if it exists
    if fileExists(configPath):
      let backupPath = configPath & ".bac"
      try:
        copyFile(configPath, backupPath)
        logInfo("config", "Backed up existing config to: " & backupPath)
      except CatchableError as ex:
        e.state.statusMessage = "Failed to backup config: " & ex.msg
        logError("config", "Failed to backup config: " & ex.msg)
        return true

    let saveResult = saveConfig(e.config)
    if saveResult.isOk:
      e.state.statusMessage = "Config saved: " & configPath
      logInfo("config", "Config saved: " & configPath)
    else:
      e.state.statusMessage = "Failed to save config: " & saveResult.error
      logError("config", "Failed to save config: " & saveResult.error)
    return true
  of hrPutConfigFile:
    # Write current configuration to file (:putConfigFile)
    let configPath = getConfigPath()

    # Backup existing config file if it exists
    if fileExists(configPath):
      let backupPath = configPath & ".bac"
      try:
        copyFile(configPath, backupPath)
        logInfo("config", "Backed up existing config to: " & backupPath)
      except CatchableError as ex:
        e.state.statusMessage = "Error: Failed to backup config: " & ex.msg
        logError("config", "Failed to backup config: " & ex.msg)
        e.setMode(EditorMode.Normal)
        return true

    let saveResult = saveConfig(e.config)
    if saveResult.isOk:
      e.state.statusMessage = "Config written: " & configPath
      logInfo("config", "Config written: " & configPath)
    else:
      e.state.statusMessage = "Failed to write config: " & saveResult.error
      logError("config", "Failed to write config: " & saveResult.error)
    e.setMode(EditorMode.Normal)
    return true
  else:
    return true # Not a config kind; caller misrouted (defensive)
