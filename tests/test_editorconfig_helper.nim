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

import std/[unittest, options, tables, os]

import pkg/results

import ../src/moepkg/[buffer, config, types]

import ../src/moepkg/editorconfig_helper {.all.}

suite "EditorConfig Support":
  test "getEditorConfigProperties with empty path returns none":
    let result = getEditorConfigProperties("")
    check result.isNone

  test "getEditorConfigProperties with non-existent editorconfig returns none":
    let result = getEditorConfigProperties("/tmp/nonexistent_dir_12345/test.nim")
    check result.isNone

  test "applyEditorConfig with indent_style space":
    var props = initTable[string, string]()
    props["indent_style"] = "space"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    check buf.editorConfig.get.expandTab == some(true)

  test "applyEditorConfig with indent_style tab":
    var props = initTable[string, string]()
    props["indent_style"] = "tab"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    check buf.editorConfig.get.expandTab == some(false)

  test "applyEditorConfig with tab_width":
    var props = initTable[string, string]()
    props["tab_width"] = "4"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    check buf.editorConfig.get.tabStop == some(4)

  test "applyEditorConfig with indent_size":
    var props = initTable[string, string]()
    props["indent_size"] = "4"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    check buf.editorConfig.get.shiftWidth == some(4)
    # indent_size also sets tabStop when tab_width is not set
    check buf.editorConfig.get.tabStop == some(4)

  test "applyEditorConfig with indent_size and tab_width":
    var props = initTable[string, string]()
    props["indent_size"] = "4"
    props["tab_width"] = "8"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    check buf.editorConfig.get.shiftWidth == some(4)
    check buf.editorConfig.get.tabStop == some(8)

  test "applyEditorConfig with indent_size tab":
    var props = initTable[string, string]()
    props["indent_size"] = "tab"
    props["tab_width"] = "8"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    check buf.editorConfig.get.shiftWidth == some(8)
    check buf.editorConfig.get.tabStop == some(8)

  test "applyEditorConfig with end_of_line lf":
    var props = initTable[string, string]()
    props["end_of_line"] = "lf"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.lineEnding == LF

  test "applyEditorConfig with end_of_line crlf":
    var props = initTable[string, string]()
    props["end_of_line"] = "crlf"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.lineEnding == CRLF

  test "applyEditorConfig with end_of_line cr":
    var props = initTable[string, string]()
    props["end_of_line"] = "cr"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.lineEnding == CR

  test "applyEditorConfig with charset utf-8":
    var props = initTable[string, string]()
    props["charset"] = "utf-8"
    let buf = newTextBuffer()
    buf.hasBom = true
    applyEditorConfig(buf, props)
    check buf.encoding == utf8
    check buf.hasBom == false

  test "applyEditorConfig with insert_final_newline true":
    var props = initTable[string, string]()
    props["insert_final_newline"] = "true"
    let buf = newTextBuffer()
    buf.endOfLine = false
    applyEditorConfig(buf, props)
    check buf.endOfLine == true

  test "applyEditorConfig with insert_final_newline false":
    var props = initTable[string, string]()
    props["insert_final_newline"] = "false"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.endOfLine == false

  test "applyEditorConfig with trim_trailing_whitespace true":
    var props = initTable[string, string]()
    props["trim_trailing_whitespace"] = "true"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    check buf.editorConfig.get.trimTrailingWhitespace == some(true)

  test "applyEditorConfig with trim_trailing_whitespace false":
    var props = initTable[string, string]()
    props["trim_trailing_whitespace"] = "false"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    check buf.editorConfig.get.trimTrailingWhitespace == some(false)

  test "applyEditorConfig with all properties":
    var props = initTable[string, string]()
    props["indent_style"] = "space"
    props["indent_size"] = "4"
    props["tab_width"] = "4"
    props["end_of_line"] = "lf"
    props["charset"] = "utf-8"
    props["trim_trailing_whitespace"] = "true"
    props["insert_final_newline"] = "true"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    let ec = buf.editorConfig.get
    check ec.expandTab == some(true)
    check ec.shiftWidth == some(4)
    check ec.tabStop == some(4)
    check ec.trimTrailingWhitespace == some(true)
    check buf.lineEnding == LF
    check buf.encoding == utf8
    check buf.endOfLine == true

  test "shouldTrimTrailingWhitespace returns false with no editorConfig":
    let buf = newTextBuffer()
    check shouldTrimTrailingWhitespace(buf) == false

  test "shouldTrimTrailingWhitespace returns true when set":
    let buf = newTextBuffer()
    var bufEc = BufferEditorConfig()
    bufEc.trimTrailingWhitespace = some(true)
    buf.editorConfig = some(bufEc)
    check shouldTrimTrailingWhitespace(buf) == true

  test "shouldTrimTrailingWhitespace returns false when explicitly false":
    let buf = newTextBuffer()
    var bufEc = BufferEditorConfig()
    bufEc.trimTrailingWhitespace = some(false)
    buf.editorConfig = some(bufEc)
    check shouldTrimTrailingWhitespace(buf) == false

  # applyEditorConfigToBuffer tests

  test "applyEditorConfigToBuffer skips when disabled":
    var conf = newEditorConfig()
    conf.editorConfig.enable = false
    let buf = newTextBuffer()
    buf.filePath = some("/tmp/test.nim")
    applyEditorConfigToBuffer(buf, conf)
    check buf.editorConfig.isNone

  test "applyEditorConfigToBuffer skips when filePath is none":
    let conf = newEditorConfig()
    let buf = newTextBuffer()
    # filePath is none by default
    applyEditorConfigToBuffer(buf, conf)
    check buf.editorConfig.isNone

  # Invalid / edge case inputs for applyEditorConfig

  test "applyEditorConfig with empty props table":
    let props = initTable[string, string]()
    let buf = newTextBuffer()
    let origLineEnding = buf.lineEnding
    let origEncoding = buf.encoding
    let origEndOfLine = buf.endOfLine
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    let ec = buf.editorConfig.get
    check ec.expandTab.isNone
    check ec.tabStop.isNone
    check ec.shiftWidth.isNone
    check ec.trimTrailingWhitespace.isNone
    # Direct buffer fields should be unchanged
    check buf.lineEnding == origLineEnding
    check buf.encoding == origEncoding
    check buf.endOfLine == origEndOfLine

  test "applyEditorConfig with invalid indent_style":
    var props = initTable[string, string]()
    props["indent_style"] = "mixed"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    check buf.editorConfig.get.expandTab.isNone

  test "applyEditorConfig with non-numeric tab_width":
    var props = initTable[string, string]()
    props["tab_width"] = "abc"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    check buf.editorConfig.get.tabStop.isNone

  test "applyEditorConfig with tab_width zero":
    var props = initTable[string, string]()
    props["tab_width"] = "0"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    check buf.editorConfig.get.tabStop.isNone

  test "applyEditorConfig with tab_width exceeding upper bound":
    var props = initTable[string, string]()
    props["tab_width"] = "999999"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    check buf.editorConfig.get.tabStop.isNone

  test "applyEditorConfig with tab_width at upper bound":
    var props = initTable[string, string]()
    props["tab_width"] = "16"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    check buf.editorConfig.get.tabStop == some(16)

  test "applyEditorConfig with indent_size tab without tab_width":
    var props = initTable[string, string]()
    props["indent_size"] = "tab"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    # tab_width not set: shiftWidth records the vim-style 0 sentinel so
    # effectiveShiftWidth() follows the effective tabStop at read time.
    check buf.editorConfig.get.shiftWidth == some(0)
    check buf.editorConfig.get.tabStop.isNone

  test "applyEditorConfig with non-numeric indent_size":
    var props = initTable[string, string]()
    props["indent_size"] = "abc"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    check buf.editorConfig.get.shiftWidth.isNone
    check buf.editorConfig.get.tabStop.isNone

  test "applyEditorConfig with indent_size zero":
    var props = initTable[string, string]()
    props["indent_size"] = "0"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    check buf.editorConfig.get.shiftWidth.isNone

  test "applyEditorConfig with indent_size exceeding upper bound":
    var props = initTable[string, string]()
    props["indent_size"] = "999999"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    check buf.editorConfig.get.shiftWidth.isNone
    check buf.editorConfig.get.tabStop.isNone

  # charset variants

  test "applyEditorConfig with charset utf-8-bom":
    var props = initTable[string, string]()
    props["charset"] = "utf-8-bom"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.encoding == utf8
    check buf.hasBom == true

  test "applyEditorConfig with charset utf-16be":
    var props = initTable[string, string]()
    props["charset"] = "utf-16be"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.encoding == utf16Be
    check buf.hasBom == true

  test "applyEditorConfig with charset utf-16le":
    var props = initTable[string, string]()
    props["charset"] = "utf-16le"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.encoding == utf16Le
    check buf.hasBom == true

  test "applyEditorConfig with charset latin1 keeps default":
    var props = initTable[string, string]()
    props["charset"] = "latin1"
    let buf = newTextBuffer()
    let origEncoding = buf.encoding
    applyEditorConfig(buf, props)
    check buf.encoding == origEncoding

  test "applyEditorConfig with unknown charset keeps default":
    var props = initTable[string, string]()
    props["charset"] = "windows-1252"
    let buf = newTextBuffer()
    let origEncoding = buf.encoding
    applyEditorConfig(buf, props)
    check buf.encoding == origEncoding

  test "applyEditorConfig with invalid end_of_line keeps default":
    var props = initTable[string, string]()
    props["end_of_line"] = "unknown"
    let buf = newTextBuffer()
    let origLineEnding = buf.lineEnding
    applyEditorConfig(buf, props)
    check buf.lineEnding == origLineEnding

  # 1. shouldTrimTrailingWhitespace with editorConfig present but field unset

  test "shouldTrimTrailingWhitespace returns false when editorConfig present but field unset":
    let buf = newTextBuffer()
    buf.editorConfig = some(BufferEditorConfig())
    check shouldTrimTrailingWhitespace(buf) == false

  # 2. Integration tests with actual .editorconfig files

  test "getEditorConfigProperties reads actual editorconfig file":
    let testDir = getTempDir() / "moe_ec_test_integration"
    let testFile = testDir / "test.nim"
    createDir(testDir)
    defer:
      removeDir(testDir)

    writeFile(
      testDir / ".editorconfig",
      """
root = true

[*.nim]
indent_style = space
indent_size = 2
tab_width = 4
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true
""",
    )
    writeFile(testFile, "echo \"hello\"\n")

    let props = getEditorConfigProperties(testFile)
    check props.isSome
    let p = props.get
    check p["indent_style"] == "space"
    check p["indent_size"] == "2"
    check p["tab_width"] == "4"
    check p["end_of_line"] == "lf"
    check p["charset"] == "utf-8"
    check p["trim_trailing_whitespace"] == "true"
    check p["insert_final_newline"] == "true"

  test "applyEditorConfigToBuffer with actual editorconfig file":
    let testDir = getTempDir() / "moe_ec_test_apply"
    let testFile = testDir / "main.py"
    createDir(testDir)
    defer:
      removeDir(testDir)

    writeFile(
      testDir / ".editorconfig",
      """
root = true

[*.py]
indent_style = space
indent_size = 4
end_of_line = lf
trim_trailing_whitespace = true
""",
    )
    writeFile(testFile, "print('hello')\n")

    let conf = newEditorConfig()
    let buf = newTextBuffer()
    buf.filePath = some(testFile)
    applyEditorConfigToBuffer(buf, conf)

    check buf.editorConfig.isSome
    let ec = buf.editorConfig.get
    check ec.expandTab == some(true)
    check ec.shiftWidth == some(4)
    check ec.tabStop == some(4)
    check ec.trimTrailingWhitespace == some(true)
    check buf.lineEnding == LF

  test "applyEditorConfigToBuffer with no matching editorconfig":
    let testDir = getTempDir() / "moe_ec_test_nomatch"
    let testFile = testDir / "test.txt"
    createDir(testDir)
    defer:
      removeDir(testDir)

    # .editorconfig with root=true but no matching section
    writeFile(
      testDir / ".editorconfig",
      """
root = true

[*.nim]
indent_size = 2
""",
    )
    writeFile(testFile, "hello\n")

    let conf = newEditorConfig()
    let buf = newTextBuffer()
    buf.filePath = some(testFile)
    applyEditorConfigToBuffer(buf, conf)

    # No properties matched for .txt, so editorConfig should remain none
    check buf.editorConfig.isNone

  test "applyEditorConfigToBuffer drops stale overrides when no section matches":
    let testDir = getTempDir() / "moe_ec_test_drop_stale"
    let testFile = testDir / "test.txt"
    createDir(testDir)
    defer:
      removeDir(testDir)

    writeFile(
      testDir / ".editorconfig",
      """
root = true

[*.nim]
indent_style = space
""",
    )
    writeFile(testFile, "hello\n")

    let conf = newEditorConfig()
    let buf = newTextBuffer()
    buf.filePath = some(testFile)
    # Simulate an override left over from a prior .editorconfig state.
    buf.editorConfig = some(BufferEditorConfig(expandTab: some(true), tabStop: some(2)))

    applyEditorConfigToBuffer(buf, conf)

    check buf.editorConfig.isNone

  # 3. Negative numeric values

  test "applyEditorConfig with negative tab_width":
    var props = initTable[string, string]()
    props["tab_width"] = "-1"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    check buf.editorConfig.get.tabStop.isNone

  test "applyEditorConfig with negative indent_size":
    var props = initTable[string, string]()
    props["indent_size"] = "-3"
    let buf = newTextBuffer()
    applyEditorConfig(buf, props)
    check buf.editorConfig.isSome
    check buf.editorConfig.get.shiftWidth.isNone
    # Negative indent_size should not set tabStop either
    check buf.editorConfig.get.tabStop.isNone

  # Raw buffers: text-transform overrides must not apply, or saving would
  # corrupt the undecodable bytes kept verbatim.

  test "applyEditorConfig skips text transforms for a raw buffer":
    # UTF-16 BOM with an odd byte count: decoding fails, buffer keeps raw bytes.
    var buf = newTextBuffer()
    discard buf.loadFileWithContent("/tmp/moe_raw_probe.bin", "\xFF\xFE\x41\x00\x0A")
    check buf.keepRaw

    var props = initTable[string, string]()
    props["insert_final_newline"] = "false"
    props["end_of_line"] = "crlf"
    props["charset"] = "utf-16le"
    props["trim_trailing_whitespace"] = "true"
    applyEditorConfig(buf, props)

    # Load values must survive: endOfLine=true (trailing \n), lineEnding=LF
    # placeholder, encoding=unknown, no trim override stored.
    check buf.endOfLine
    check buf.lineEnding == LF
    check buf.encoding == CharacterEncoding.unknown
    check buf.editorConfig.get.trimTrailingWhitespace.isNone

  test "raw buffer save is not corrupted by insert_final_newline":
    let content = "\xFF\xFE\x41\x00\x0A"
    let testFile = getTempDir() / "moe_raw_ec_save.bin"
    writeFile(testFile, content)
    defer:
      removeFile(testFile)

    var buf = newTextBuffer()
    discard buf.loadFile(testFile)
    check buf.keepRaw

    var props = initTable[string, string]()
    props["insert_final_newline"] = "false"
    applyEditorConfig(buf, props)

    check buf.saveFile(testFile).isOk
    check readFile(testFile) == content
