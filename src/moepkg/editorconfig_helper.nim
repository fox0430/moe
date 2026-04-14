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

## EditorConfig support
##
## This module integrates the editorconfig-nim library to automatically apply
## per-file settings based on .editorconfig files.

import std/[options, tables, strutils, os]

import pkg/editorconfig

import buffer, config, types, logger

proc getEditorConfigProperties*(filePath: string): Option[Table[string, string]] =
  ## Get EditorConfig properties for a file path.
  ## Returns none if the file path is empty or properties cannot be retrieved.
  if filePath.len == 0:
    return none(Table[string, string])

  try:
    let absPath = absolutePath(filePath)
    # Check that the parent directory exists to avoid a bug in the editorconfig
    # library where parentDir reaches "" and falls back to CWD.
    ## TODO: Remove after resolved (https://github.com/fox0430/editorconfig-nim/issues/7)
    if not dirExists(parentDir(absPath)):
      return none(Table[string, string])
    let props = getProperties(absPath)
    if props.len > 0:
      return some(props)
    else:
      return none(Table[string, string])
  except CatchableError as e:
    logDebug("editorconfig", "Failed to get properties for " & filePath & ": " & e.msg)
    return none(Table[string, string])

proc applyEditorConfig*(buffer: TextBuffer, props: Table[string, string]) =
  ## Apply EditorConfig properties to a TextBuffer.
  ## Sets per-buffer overrides in buffer.editorConfig and direct buffer fields.

  var bufEc = BufferEditorConfig()

  # indent_style -> expandTab
  if props.hasKey("indent_style"):
    let style = props["indent_style"]
    if style == "space":
      bufEc.expandTab = some(true)
    elif style == "tab":
      bufEc.expandTab = some(false)

  # tab_width -> tabStop
  if props.hasKey("tab_width"):
    try:
      let val = parseInt(props["tab_width"])
      if val > 0:
        bufEc.tabStop = some(val)
    except ValueError:
      discard

  # indent_size -> shiftWidth (and tabStop if tab_width not set)
  if props.hasKey("indent_size"):
    let sizeStr = props["indent_size"]
    if sizeStr == "tab":
      # indent_size = tab means use tab_width value
      if bufEc.tabStop.isSome:
        bufEc.shiftWidth = bufEc.tabStop
    else:
      try:
        let val = parseInt(sizeStr)
        if val > 0:
          bufEc.shiftWidth = some(val)
          # If tab_width was not explicitly set, indent_size also sets tabStop
          if not props.hasKey("tab_width"):
            bufEc.tabStop = some(val)
      except ValueError:
        discard

  # trim_trailing_whitespace
  if props.hasKey("trim_trailing_whitespace"):
    let val = props["trim_trailing_whitespace"]
    if val == "true":
      bufEc.trimTrailingWhitespace = some(true)
    elif val == "false":
      bufEc.trimTrailingWhitespace = some(false)

  buffer.editorConfig = some(bufEc)

  # end_of_line -> lineEnding (set directly on buffer)
  if props.hasKey("end_of_line"):
    let eol = props["end_of_line"]
    case eol
    of "lf":
      buffer.lineEnding = LF
    of "crlf":
      buffer.lineEnding = CRLF
    of "cr":
      buffer.lineEnding = CR
    else:
      discard

  # charset -> encoding (set directly on buffer)
  if props.hasKey("charset"):
    let cs = props["charset"]
    case cs
    of "utf-8", "utf-8-bom":
      buffer.encoding = utf8
    of "utf-16be":
      buffer.encoding = utf16Be
    of "utf-16le":
      buffer.encoding = utf16Le
    of "latin1":
      # latin1 is not directly supported, keep as utf8
      discard
    else:
      discard

  # insert_final_newline -> endOfLine (set directly on buffer)
  if props.hasKey("insert_final_newline"):
    let val = props["insert_final_newline"]
    if val == "true":
      buffer.endOfLine = true
    elif val == "false":
      buffer.endOfLine = false

  logDebug(
    "editorconfig",
    "Applied EditorConfig to " & buffer.filePath.get("(unnamed)") & ": " & $props,
  )

proc applyBufferEditorConfig*(
    display: var DisplaySettings, buffer: TextBuffer, config: EditorConfig
) =
  ## Apply per-buffer EditorConfig overrides to DisplaySettings.
  ## Falls back to global config values for fields not overridden.

  # Always reset to global config values first
  display.tabStop = config.standard.tabStop
  display.shiftWidth = config.standard.shiftWidth
  display.expandTab = config.standard.expandTab

  # Apply per-buffer overrides if present
  if buffer.editorConfig.isSome:
    let ec = buffer.editorConfig.get
    if ec.tabStop.isSome:
      display.tabStop = ec.tabStop.get
    if ec.shiftWidth.isSome:
      display.shiftWidth = ec.shiftWidth.get
    if ec.expandTab.isSome:
      display.expandTab = ec.expandTab.get

proc applyEditorConfigToBuffer*(buffer: TextBuffer, config: EditorConfig) =
  ## Convenience proc that gets EditorConfig properties and applies them
  ## to a buffer. Does nothing if EditorConfig is disabled or buffer has no path.
  if not config.editorConfig.enable or buffer.filePath.isNone:
    return

  let props = getEditorConfigProperties(buffer.filePath.get)
  if props.isSome:
    applyEditorConfig(buffer, props.get)

proc shouldTrimTrailingWhitespace*(buffer: TextBuffer): bool =
  ## Check if the buffer has EditorConfig trim_trailing_whitespace enabled.
  if buffer.editorConfig.isSome:
    let ec = buffer.editorConfig.get
    if ec.trimTrailingWhitespace.isSome:
      return ec.trimTrailingWhitespace.get
