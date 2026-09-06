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

suite "resolveEditorConfig - what was not applied":
  # `resolveEditorConfig` takes no buffer, so the whole matrix of
  # value x buffer kind is reachable without building one.

  proc issueFor(key, val: string, allowsTextTransforms = true): Option[SettingIssue] =
    var props = initTable[string, string]()
    props[key] = val
    let r = resolveEditorConfig(props, allowsTextTransforms)
    if r.issues.len > 0:
      some(r.issues[0])
    else:
      none(SettingIssue)

  test "a typo in a value is reported":
    for (key, val) in [
      ("indent_style", "spaces"),
      ("end_of_line", "lfcr"),
      ("trim_trailing_whitespace", "yes"),
      ("insert_final_newline", "1"),
      ("charset", "sjis"),
    ]:
      let issue = issueFor(key, val)
      check issue.isSome
      check issue.get.kind == sikInvalidValue
      check issue.get.name == key
      check issue.get.val == val

  test "a typo is reported on a raw buffer too":
    # A typo is the user's mistake wherever it lands; reported as moe's own
    # limit it would end up in a debug-only note.
    for (key, val) in [
      ("end_of_line", "lfcr"),
      ("trim_trailing_whitespace", "yes"),
      ("insert_final_newline", "1"),
      ("charset", "sjis"),
    ]:
      let issue = issueFor(key, val, allowsTextTransforms = false)
      check issue.isSome
      check issue.get.kind == sikInvalidValue

  test "a valid value a raw buffer cannot honour is left to the log":
    for (key, val) in [
      ("end_of_line", "crlf"),
      ("trim_trailing_whitespace", "true"),
      ("insert_final_newline", "false"),
      ("charset", "utf-8"),
    ]:
      var props = initTable[string, string]()
      props[key] = val
      let r = resolveEditorConfig(props, allowsTextTransforms = false)
      check r.issues.len == 0
      check r.notApplicable == @[key]

  test "latin1 is unsupported rather than invalid":
    # Spec-valid, and moe has no decoder for it: the user's file is not wrong.
    let issue = issueFor("charset", "latin1")
    check issue.isSome
    check issue.get.kind == sikUnsupported

  test "latin1 on a raw buffer is left to the log like any other charset":
    # No charset applies to a raw buffer, so singling latin1 out would warn
    # about the one value the user can do nothing about.
    var props = initTable[string, string]()
    props["charset"] = "latin1"
    let r = resolveEditorConfig(props, allowsTextTransforms = false)
    check r.issues.len == 0
    check r.notApplicable == @["charset"]

suite "resolveEditorConfig - the indent pair":
  proc resolve(size, width: string): ResolvedEditorConfig =
    var props = initTable[string, string]()
    if size.len > 0:
      props["indent_size"] = size
    if width.len > 0:
      props["tab_width"] = width
    resolveEditorConfig(props, allowsTextTransforms = true)

  test "an equal pair is reported once under both names":
    # The library synthesizes either of the pair from the other, so an equal
    # pair cannot be traced back to the line the user wrote.
    let r = resolve("99", "99")
    check r.issues.len == 1
    check r.issues[0].name == "indent_size/tab_width"
    check r.issues[0].val == "99"

  test "an unequal pair is two lines the user wrote, so both are reported":
    let r = resolve("99", "98")
    check r.issues.len == 2
    check r.issues[0].name == "tab_width"
    check r.issues[1].name == "indent_size"

  test "a shared \"tab\" names only tab_width":
    # Only tab_width refuses it; naming the pair would report an indent_size
    # that was honoured as dropped.
    let r = resolve("tab", "tab")
    check r.issues.len == 1
    check r.issues[0].name == "tab_width"
    check r.bufferConfig.shiftWidth == some(0)

  test "a rejected tab_width does not swallow the indent_size fallback":
    let r = resolve("4", "0")
    check r.bufferConfig.tabStop == some(4)
    check r.bufferConfig.shiftWidth == some(4)
    check r.issues.len == 1

  test "a non-numeric value is reported like an out-of-range one":
    check resolve("", "x").issues[0].kind == sikInvalidValue
    check resolve("x", "").issues[0].kind == sikInvalidValue

suite "applyEditorConfig - what the buffer owes the user":
  test "issues are queued once and re-applying the same file says nothing":
    var props = initTable[string, string]()
    props["tab_width"] = "99"
    let buf = newTextBuffer()
    buf.filePath = some(getTempDir() / "moe-ec-notice.txt")

    applyEditorConfig(buf, props)
    check buf.pendingNotices.len == 1
    check buf.pendingNotices[0].kind == bnSetting

    # An auto-reload re-applies the same file, so there is nothing new to
    # say.
    discard buf.takeNotices()
    applyEditorConfig(buf, props)
    check buf.pendingNotices.len == 0

  test "an issue that goes away and comes back is queued again":
    var bad = initTable[string, string]()
    bad["tab_width"] = "99"
    let buf = newTextBuffer()
    buf.filePath = some(getTempDir() / "moe-ec-notice-again.txt")

    applyEditorConfig(buf, bad)
    discard buf.takeNotices()

    var good = initTable[string, string]()
    good["tab_width"] = "4"
    applyEditorConfig(buf, good)
    check buf.pendingNotices.len == 0

    applyEditorConfig(buf, bad)
    check buf.pendingNotices.len == 1

  test "a buffer nothing shows keeps what it owes":
    # `:lspRename` loads project files with no window on them; the notices
    # belong to the buffer, not to the act of opening it.
    var props = initTable[string, string]()
    props["tab_width"] = "99"
    let buf = newTextBuffer()
    buf.filePath = some(getTempDir() / "moe-ec-notice-unshown.txt")

    applyEditorConfig(buf, props)
    applyEditorConfig(buf, props)
    check buf.pendingNotices.len == 1

  test "a reset between applies does not queue the same issue twice":
    # The apply path clears `settingIssues` when editorconfig is off or the
    # file cannot be read, and a buffer no window drains still holds what it
    # owes.
    var props = initTable[string, string]()
    props["tab_width"] = "99"
    let buf = newTextBuffer()
    buf.filePath = some(getTempDir() / "moe-ec-notice-reset.txt")

    applyEditorConfig(buf, props)
    buf.settingIssues = @[]
    applyEditorConfig(buf, props)
    check buf.pendingNotices.len == 1

  test "what only the log hears is not queued":
    var buf = newTextBuffer()
    discard buf.loadFileWithContent(
      getTempDir() / "moe_raw_notice_probe.bin", "\xFF\xFE\x41\x00\x0A"
    )
    check buf.keepRaw
    discard buf.takeNotices()

    var props = initTable[string, string]()
    props["charset"] = "utf-8"
    applyEditorConfig(buf, props)

    check buf.pendingNotices.len == 0
