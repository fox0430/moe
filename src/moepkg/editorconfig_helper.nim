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

import buffer/core, config, logger

const MaxTabWidth = 16
  ## Matches the global config cfgMax for Standard.tabStop/shiftWidth.

proc getEditorConfigProperties*(filePath: string): Option[Table[string, string]] =
  ## Get EditorConfig properties for a file path.
  ## Returns none if the file path is empty or properties cannot be retrieved.
  if filePath.len == 0:
    return none(Table[string, string])

  try:
    let absPath = absolutePath(filePath)
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
      if val > 0 and val <= MaxTabWidth:
        bufEc.tabStop = some(val)
    except ValueError:
      discard

  # indent_size -> shiftWidth (and tabStop if tab_width not set)
  if props.hasKey("indent_size"):
    let sizeStr = props["indent_size"]
    if sizeStr == "tab":
      # indent_size = tab: shiftWidth follows the tab width. Mirror
      # tab_width when set; otherwise store 0, the vim-style "follow
      # tabStop" sentinel that effectiveShiftWidth() resolves at read.
      bufEc.shiftWidth =
        if bufEc.tabStop.isSome:
          bufEc.tabStop
        else:
          some(0)
    else:
      try:
        let val = parseInt(sizeStr)
        if val > 0 and val <= MaxTabWidth:
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
    of "utf-8":
      buffer.encoding = utf8
      buffer.hasBom = false
    of "utf-8-bom":
      buffer.encoding = utf8
      buffer.hasBom = true
    of "utf-16be":
      buffer.encoding = utf16Be
      # UTF-16 needs a BOM for endianness detection on reload
      buffer.hasBom = true
    of "utf-16le":
      buffer.encoding = utf16Le
      buffer.hasBom = true
    of "latin1":
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

proc applyEditorConfigToBuffer*(buffer: TextBuffer, config: EditorConfig) =
  ## Convenience proc that gets EditorConfig properties and applies them
  ## to a buffer. Does nothing if EditorConfig is disabled or buffer has no path.
  if not config.editorConfig.enable or buffer.filePath.isNone:
    return

  let props = getEditorConfigProperties(buffer.filePath.get)
  if props.isSome:
    applyEditorConfig(buffer, props.get)
  else:
    # No matching section (or file removed) — drop stale overrides so a reload
    # falls back to the global config.
    buffer.editorConfig = none(BufferEditorConfig)

proc shouldTrimTrailingWhitespace*(buffer: TextBuffer): bool =
  ## Check if the buffer has EditorConfig trim_trailing_whitespace enabled.
  if buffer.editorConfig.isSome:
    let ec = buffer.editorConfig.get
    if ec.trimTrailingWhitespace.isSome:
      return ec.trimTrailingWhitespace.get
