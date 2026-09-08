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

import buffer/core, config, logger, setting_issue

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

type ResolvedEditorConfig* = object
  ## What `.editorconfig` asks of a buffer, worked out without touching one.
  bufferConfig*: BufferEditorConfig
  lineEnding*: Option[LineEnding]
  encoding*: Option[CharacterEncoding]
  hasBom*: Option[bool]
  endOfLine*: Option[bool]
  issues*: seq[SettingIssue]
    ## Values the user should hear about: a mistake in their own file, or
    ## something moe does not implement.
  notApplicable*: seq[string]
    ## Properties this buffer cannot honour whatever their value. moe's own
    ## limit, so only the log hears it.

proc note(
    r: var ResolvedEditorConfig, kind: SettingIssueKind, key, val, expected: string
) =
  r.issues.add SettingIssue(kind: kind, name: key, val: val, expected: expected)

proc accept(
    r: var ResolvedEditorConfig,
    key, val: string,
    allowed: openArray[string],
    expected: string,
    applicable: bool,
): bool =
  ## Whether `key` should be applied, and the note for it when it should not.
  ## Validity is checked before applicability, so a typo is reported even on a
  ## buffer that could not have honoured the property.
  if val notin allowed:
    r.note(sikInvalidValue, key, val, expected)
    return false
  if not applicable:
    r.notApplicable.add key
    return false
  true

proc resolveIndent(r: var ResolvedEditorConfig, props: Table[string, string]) =
  ## Work out `tabStop` and `shiftWidth`.
  ##
  ## The library synthesizes `indent_size` and `tab_width` from each other, so
  ## an equal pair cannot be traced back to the line the user wrote and a
  ## message names both keys. A shared "tab" is the exception: only `tab_width`
  ## refuses it, and naming the pair would report an honoured `indent_size` as
  ## dropped.
  const Range = "a number in 1.." & $MaxTabWidth
  let
    widthStr = props.getOrDefault("tab_width")
    sizeStr = props.getOrDefault("indent_size")
    shared = widthStr.len > 0 and widthStr == sizeStr and widthStr != "tab"
    pairName = "indent_size/tab_width"

  if widthStr.len > 0:
    let val =
      try:
        parseInt(widthStr)
      except ValueError:
        0
    if val > 0 and val <= MaxTabWidth:
      r.bufferConfig.tabStop = some(val)
    else:
      r.note(sikInvalidValue, (if shared: pairName else: "tab_width"), widthStr, Range)

  if sizeStr.len == 0:
    return

  if sizeStr == "tab":
    # shiftWidth follows the tab width: mirror tab_width when set, otherwise
    # store 0, the "follow tabStop" sentinel effectiveShiftWidth() resolves.
    r.bufferConfig.shiftWidth =
      if r.bufferConfig.tabStop.isSome:
        r.bufferConfig.tabStop
      else:
        some(0)
    return

  let val =
    try:
      parseInt(sizeStr)
    except ValueError:
      0
  if val > 0 and val <= MaxTabWidth:
    r.bufferConfig.shiftWidth = some(val)
    # indent_size also sets tabStop unless tab_width already did. Keyed on what
    # was applied, so a rejected tab_width does not swallow the fallback.
    if r.bufferConfig.tabStop.isNone:
      r.bufferConfig.tabStop = some(val)
  elif not shared:
    # A shared pair has already been reported under both names.
    r.note(sikInvalidValue, "indent_size", sizeStr, Range & ' ' & "or \"tab\"")

proc resolveEditorConfig*(
    props: Table[string, string], allowsTextTransforms: bool
): ResolvedEditorConfig =
  ## Work out what `props` asks for and what of it moe drops. Applies nothing;
  ## `applyEditorConfig` does that.

  if props.hasKey("indent_style"):
    let style = props["indent_style"]
    if result.accept(
      "indent_style", style, ["space", "tab"], "\"space\" or \"tab\"", true
    ):
      result.bufferConfig.expandTab = some(style == "space")

  result.resolveIndent(props)

  # Trimming would corrupt raw bytes.
  if props.hasKey("trim_trailing_whitespace"):
    let val = props["trim_trailing_whitespace"]
    if result.accept(
      "trim_trailing_whitespace",
      val,
      ["true", "false"],
      "\"true\" or \"false\"",
      allowsTextTransforms,
    ):
      result.bufferConfig.trimTrailingWhitespace = some(val == "true")

  # `lineEnding` is unused for raw buffers (shows RAW).
  if props.hasKey("end_of_line"):
    let eol = props["end_of_line"]
    if result.accept(
      "end_of_line",
      eol,
      ["lf", "crlf", "cr"],
      "\"lf\", \"crlf\" or \"cr\"",
      allowsTextTransforms,
    ):
      result.lineEnding = some(
        case eol
        of "lf": LF
        of "crlf": CRLF
        else: CR
      )

  # The encoding of a raw buffer is unknown.
  if props.hasKey("charset"):
    const Known = ["utf-8", "utf-8-bom", "utf-16be", "utf-16le", "latin1"]
    let cs = props["charset"]
    if result.accept(
      "charset", cs, Known, "one of " & Known.join(", "), allowsTextTransforms
    ):
      case cs
      of "utf-8":
        result.encoding = some(CharacterEncoding.utf8)
        result.hasBom = some(false)
      of "utf-8-bom":
        result.encoding = some(CharacterEncoding.utf8)
        result.hasBom = some(true)
      of "utf-16be":
        result.encoding = some(CharacterEncoding.utf16Be)
        # UTF-16 needs a BOM for endianness detection on reload
        result.hasBom = some(true)
      of "utf-16le":
        result.encoding = some(CharacterEncoding.utf16Le)
        result.hasBom = some(true)
      else:
        # Spec-valid but moe has no decoder for it, so not an invalid value.
        result.note(
          sikUnsupported, "charset", cs, "moe reads and writes UTF-8 and UTF-16 only"
        )

  # Adding or removing a final newline would corrupt raw bytes on save.
  if props.hasKey("insert_final_newline"):
    let val = props["insert_final_newline"]
    if result.accept(
      "insert_final_newline",
      val,
      ["true", "false"],
      "\"true\" or \"false\"",
      allowsTextTransforms,
    ):
      result.endOfLine = some(val == "true")

proc applyEditorConfig*(buffer: TextBuffer, r: ResolvedEditorConfig) =
  ## Write `r` onto `buffer` and queue the issues the user should hear about.
  ## Log-only notes are written here instead of carried on the buffer.
  buffer.editorConfig = some(r.bufferConfig)
  if r.lineEnding.isSome:
    buffer.lineEnding = r.lineEnding.get
  if r.encoding.isSome:
    buffer.encoding = r.encoding.get
  if r.hasBom.isSome:
    buffer.hasBom = r.hasBom.get
  if r.endOfLine.isSome:
    buffer.endOfLine = r.endOfLine.get

  buffer.noteSettingIssues(r.issues)
  if r.notApplicable.len > 0:
    logDebug(
      "editorconfig",
      "Not applicable to " & buffer.filePath.get("(unnamed)") & " (held raw): " &
        r.notApplicable.join(", "),
    )

proc applyEditorConfig*(buffer: TextBuffer, props: Table[string, string]) =
  ## Resolve `props` for `buffer` and apply the result.
  buffer.applyEditorConfig(resolveEditorConfig(props, buffer.allowsTextTransforms))

proc applyEditorConfigToBuffer*(buffer: TextBuffer, config: EditorConfig) =
  ## Convenience proc that gets EditorConfig properties and applies them
  ## to a buffer. Does nothing if EditorConfig is disabled or buffer has no path.
  if not config.editorConfig.enable or buffer.filePath.isNone:
    buffer.noteSettingIssues(@[])
    return

  let props = getEditorConfigProperties(buffer.filePath.get)
  if props.isSome:
    buffer.applyEditorConfig(
      resolveEditorConfig(props.get, buffer.allowsTextTransforms)
    )
    logDebug(
      "editorconfig",
      "Applied EditorConfig to " & buffer.filePath.get & ": " & $props.get,
    )
  else:
    # No matching section (or file removed) — drop stale overrides so a reload
    # falls back to the global config.
    buffer.editorConfig = none(BufferEditorConfig)
    buffer.noteSettingIssues(@[])

proc shouldTrimTrailingWhitespace*(buffer: TextBuffer): bool =
  ## Check if the buffer has EditorConfig trim_trailing_whitespace enabled.
  if buffer.editorConfig.isSome:
    let ec = buffer.editorConfig.get
    if ec.trimTrailingWhitespace.isSome:
      return ec.trimTrailingWhitespace.get
