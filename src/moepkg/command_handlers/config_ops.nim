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

type ConfigWriteError* = object
  backupFailed*: bool ## The copy of the old file failed, so nothing was written.
  reason*: string

proc writeConfigFile*(e: Editor): Result[string, ConfigWriteError] =
  ## Write the settings to the config file, backing up the one there first.
  ## The path written, or why nothing was.
  let configPath = getConfigPath()
  if fileExists(configPath):
    let backupPath = configPath & ".bac"
    try:
      copyFile(configPath, backupPath)
      logInfo("config", "Backed up existing config to: " & backupPath)
    except CatchableError as ex:
      logError("config", "Failed to backup config: " & ex.msg)
      return err(ConfigWriteError(backupFailed: true, reason: ex.msg))
  let saveResult = saveConfig(e.config)
  if saveResult.isErr:
    return err(ConfigWriteError(reason: saveResult.error))
  ok(configPath)

proc saveFailedMessage*(error: ConfigWriteError): string =
  ## Why saving the settings failed, as Config's `:w` says it.
  if error.backupFailed:
    return "Failed to backup config: " & error.reason
  logError("config", "Failed to save config: " & error.reason)
  "Failed to save config: " & error.reason

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
    e.leaveViewerMode(EditorMode.Config)
    return true
  of hrConfigSaveConfig:
    let written = e.writeConfigFile()
    if written.isOk:
      e.state.statusMessage = "Config saved: " & written.get
      logInfo("config", "Config saved: " & written.get)
    else:
      e.state.statusMessage = written.error.saveFailedMessage
    return true
  of hrPutConfigFile:
    # Write current configuration to file (:putConfigFile)
    let written = e.writeConfigFile()
    if written.isOk:
      e.state.statusMessage = "Config written: " & written.get
      logInfo("config", "Config written: " & written.get)
    elif written.error.backupFailed:
      e.state.statusMessage = "Error: Failed to backup config: " & written.error.reason
    else:
      e.state.statusMessage = "Failed to write config: " & written.error.reason
      logError("config", "Failed to write config: " & written.error.reason)
    return true
  else:
    return true # Not a config kind; caller misrouted (defensive)
