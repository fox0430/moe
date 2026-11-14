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

import std/[unittest, options, os, sequtils, strutils, times]

import pkg/results

import ../src/moepkg/[config_loader, config, hook_ex_command, hooks]
import ../src/moepkg/command_line/range_parser
import ../src/moepkg/syntax/tokenizer

var testFileCounter {.global.} = 0

proc loadFromTomlString(tomlStr: string): (EditorConfig, ValidationResult) =
  inc testFileCounter
  let testFile = getTempDir() / "moe_test_hooks_" & $testFileCounter & ".toml"
  writeFile(testFile, tomlStr)
  defer:
    removeFile(testFile)

  let loadResult = loadConfigFromToml(testFile)
  check loadResult.isOk
  return loadResult.get

suite "Hooks - filetype names":
  test "Enum name without the lang prefix, lowercased":
    check filetypeName(SourceLanguage.langNim) == "nim"
    check filetypeName(SourceLanguage.langJavaScript) == "javascript"
    check filetypeName(SourceLanguage.langCpp) == "cpp"
    check filetypeName(SourceLanguage.langNone) == "none"

  test "Every language has a distinct name":
    var seen: seq[string]
    for language in SourceLanguage:
      let name = filetypeName(language)
      check name notin seen
      if language != SourceLanguage.langNone:
        check isValidFiletype(name)
      seen.add name

  test "Unknown name is rejected":
    check not isValidFiletype("nimrod")
    check not isValidFiletype("")

  test "\"none\" is rejected":
    # No completion offers it, so accepting it builds an entry the user cannot
    # have meant and can only discover by it never running.
    check not isValidFiletype("none")
    check filetypeLanguage("none").isNone

  test "Every display name is accepted too":
    # The name the rest of the editor shows and `getSourceLanguage` parses, so
    # `filetype = ["JavaScriptReact"]` is not silently a typo.
    for language in SourceLanguage:
      if language == SourceLanguage.langNone:
        continue
      let display = sourceLanguageToStr[language]
      check isValidFiletype(display)
      check filetypeLanguage(display) == some(language)

  test "Abbreviations are accepted":
    check filetypeLanguage("tsx") == some(SourceLanguage.langTsx)
    check filetypeLanguage("py") == some(SourceLanguage.langPython)
    check filetypeLanguage("C++") == some(SourceLanguage.langCpp)
    check filetypeLanguage("git-rebase-todo") == some(SourceLanguage.langGitRebaseTodo)

  test "An entry matches whichever spelling it used":
    let entries = @[
      HookEntry(event: heBufWritePost, command: "true", filetype: @["tsx"]),
      HookEntry(event: heBufWritePost, command: "true", filetype: @["TypeScriptReact"]),
    ]
    for entry in entries:
      check entry.matches(heBufWritePost, "/src/a.tsx", SourceLanguage.langTsx)
      check not entry.matches(
        heBufWritePost, "/src/a.ts", SourceLanguage.langTypeScript
      )

suite "Hooks - matching":
  test "Event must match":
    let entry = HookEntry(event: heBufWritePost, command: "true")
    check entry.matches(heBufWritePost, "/tmp/a.nim", langNim)
    check not entry.matches(heBufReadPost, "/tmp/a.nim", langNim)

  test "Empty filetype and filter match everything":
    let entry = HookEntry(event: heBufWritePost, command: "true")
    check entry.matches(heBufWritePost, "/tmp/a.go", langGo)
    check entry.matches(heBufWritePost, "", langNone)

  test "Filetype restricts by language, not by extension":
    let entry =
      HookEntry(event: heBufWritePost, command: "true", filetype: @["nim", "go"])
    check entry.matches(heBufWritePost, "/tmp/a.nim", langNim)
    check entry.matches(heBufWritePost, "/tmp/a.go", langGo)
    # The path says nim, the buffer says rust: the buffer wins.
    check not entry.matches(heBufWritePost, "/tmp/a.nim", langRust)

  test "Filter is an unanchored regex over the path":
    let entry = HookEntry(event: heBufWritePost, command: "true", filter: r"\.go$")
    check entry.matches(heBufWritePost, "/tmp/a.go", langGo)
    check not entry.matches(heBufWritePost, "/tmp/a.gox", langGo)
    check not entry.matches(heBufWritePost, "/tmp/go.nim", langNim)

  test "A path that is not valid UTF-8 is matched as displayed":
    # `regex` asserts on invalid UTF-8 input, and its behaviour there is
    # undefined in release. A file name is bytes, so the undecodable ones are
    # matched as the U+FFFD the path would be displayed with.
    let entry = HookEntry(event: heBufWritePost, command: "true", filter: r"\.go$")
    check entry.matches(heBufWritePost, "/tmp/a\x80b.go", langGo)
    check not entry.matches(heBufWritePost, "/tmp/a\x80b.gox", langGo)

    # The byte is one replacement character to the filter.
    let named = HookEntry(event: heBufWritePost, command: "true", filter: "\uFFFD")
    check named.matches(heBufWritePost, "/tmp/a\x80b.go", langGo)

  test "Filetype and filter both have to match":
    let entry = HookEntry(
      event: heBufWritePost, command: "true", filetype: @["nim"], filter: r"^/src/"
    )
    check entry.matches(heBufWritePost, "/src/a.nim", langNim)
    check not entry.matches(heBufWritePost, "/tests/a.nim", langNim)
    check not entry.matches(heBufWritePost, "/src/a.go", langGo)

suite "Hooks - command expansion":
  test "Placeholders":
    let entry = HookEntry(
      event: heBufWritePost,
      command: "fmt ${file} ${dir} ${filename} ${basename} ${ext} ${filetype}",
    )
    let command = entry.toCommand("/src/pkg/main.nim", langNim)
    check command.cmd == "fmt"
    check command.args ==
      @["/src/pkg/main.nim", "/src/pkg", "main.nim", "main", "nim", "nim"]

  test "A path with spaces stays one argument":
    let entry = HookEntry(event: heBufWritePost, command: "fmt -w ${file}")
    let command = entry.toCommand("/src/my dir/a b.nim", langNim)
    check command.args == @["-w", "/src/my dir/a b.nim"]

  test "A path cannot inject further arguments":
    let entry = HookEntry(event: heBufWritePost, command: "fmt ${file}")
    let command = entry.toCommand("/tmp/a.nim --dangerous 'x y'", langNim)
    check command.args == @["/tmp/a.nim --dangerous 'x y'"]

  test "Unknown placeholders are left verbatim":
    let entry = HookEntry(event: heBufWritePost, command: "sh -c ${HOME}/x")
    check entry.toCommand("/tmp/a.nim", langNim).args == @["-c", "${HOME}/x"]

  test "A file without an extension expands ext to nothing":
    let entry = HookEntry(event: heBufWritePost, command: "fmt ${basename}.${ext}")
    check entry.toCommand("/tmp/Makefile", langNone).args == @["Makefile."]

  test "workingDir defaults to the file's directory":
    let entry = HookEntry(event: heBufWritePost, command: "fmt")
    check entry.toCommand("/src/pkg/main.nim", langNim).workingDir == "/src/pkg"

  test "A placeholder-like directory name is not expanded in the default workingDir":
    # The default is built from the file's own path, not from a template: a
    # literal `${...}` in it must survive, or the command starts elsewhere.
    let entry = HookEntry(event: heBufWritePost, command: "fmt")
    check entry.toCommand("/tmp/${basename}/proj/a.nim", langNim).workingDir ==
      "/tmp/${basename}/proj"

  test "workingDir is expanded and tilde-resolved":
    let entry =
      HookEntry(event: heBufWritePost, command: "fmt", workingDir: "~/proj/${filetype}")
    check entry.toCommand("/src/main.nim", langNim).workingDir ==
      getHomeDir() / "proj/nim"

  test "A leading tilde resolves in the command and in its arguments":
    # There is no shell to do it, and `~/bin/fmt` would simply not be found.
    let entry = HookEntry(event: heBufWritePost, command: "~/bin/fmt -c ~/fmt.cfg")
    let command = entry.toCommand("/src/main.nim", langNim)
    check command.cmd == getHomeDir() / "bin/fmt"
    check command.args == @["-c", getHomeDir() / "fmt.cfg"]

  test "A tilde inside an argument is left alone":
    let entry = HookEntry(event: heBufWritePost, command: "fmt --backup=a~ x~/y")
    check entry.toCommand("/src/main.nim", langNim).args == @["--backup=a~", "x~/y"]

  test "A file name starting with a tilde is not taken for the home directory":
    # Only a tilde the user wrote is theirs to expand; `~.nim` gives `~`.
    let entry = HookEntry(
      event: heBufWritePost,
      command: "fmt ${basename} ${filename}",
      workingDir: "${dir}",
    )
    let command = entry.toCommand("/src/~.nim", langNim)
    check command.args == @["~", "~.nim"]
    check command.workingDir == "/src"

  test "An empty command line yields no cmd to exec":
    let entry = HookEntry(event: heBufWritePost, command: "   ")
    check entry.toCommand("/tmp/a.nim", langNim).cmd == ""

suite "Hooks - selection":
  const config = HookConfig(
    enable: true,
    entries: @[
      HookEntry(event: heBufWritePost, command: "first", filetype: @["nim"]),
      HookEntry(event: heBufWritePost, command: "second"),
      HookEntry(event: heBufReadPost, command: "third"),
    ],
  )

  test "Matching entries are returned in config order":
    let selected = config.hooksFor(heBufWritePost, "/tmp/a.nim", langNim)
    check selected.len == 2
    check selected[0].command == "first"
    check selected[1].command == "second"

  test "Non-matching entries are skipped":
    check config.hooksFor(heBufWritePost, "/tmp/a.go", langGo).mapIt(it.command) ==
      @["second"]
    check config.hooksFor(heBufReadPost, "/tmp/a.nim", langNim).mapIt(it.command) ==
      @["third"]

  test "A pathless buffer fires nothing":
    check config.hooksFor(heBufWritePost, "", langNim).len == 0

  test "enable = false fires nothing":
    var disabled = config
    disabled.enable = false
    check disabled.hooksFor(heBufWritePost, "/tmp/a.nim", langNim).len == 0

suite "Hooks - config loading":
  test "Defaults":
    let (config, vr) = loadFromTomlString("")
    check not vr.hasErrors
    check config.hooks.enable
    check not config.hooks.onAutoSave
    check config.hooks.exitWaitTimeout == DefaultHookExitWaitTimeout
    check config.hooks.entries.len == 0

  test "A full entry":
    let (config, vr) = loadFromTomlString(
      """
[Hook]
enable = true
onAutoSave = true
exitWaitTimeout = 3

[[Hook.entries]]
event = "BufWritePost"
filetype = ["nim"]
filter = "\\.nim$"
command = "nph ${file}"
workingDir = "/src"
timeout = 5
showOutput = true
"""
    )
    check not vr.hasErrors
    check config.hooks.onAutoSave
    check config.hooks.exitWaitTimeout == 3
    check config.hooks.entries.len == 1
    let entry = config.hooks.entries[0]
    check entry.event == heBufWritePost
    check entry.filetype == @["nim"]
    check entry.filter == r"\.nim$"
    check entry.command == "nph ${file}"
    check entry.workingDir == "/src"
    check entry.timeout == 5
    check entry.showOutput

  test "Omitted keys take their defaults":
    let (config, vr) = loadFromTomlString(
      """
[[Hook.entries]]
event = "BufReadPost"
command = "true"
"""
    )
    check not vr.hasErrors
    let entry = config.hooks.entries[0]
    check entry.event == heBufReadPost
    check entry.filetype.len == 0
    check entry.filter.len == 0
    check entry.timeout == DefaultHookTimeout
    check not entry.showOutput

  test "An entry that names no timeout takes the default":
    let (config, vr) = loadFromTomlString(
      """
[[Hook.entries]]
event = "BufWritePost"
command = "true"
"""
    )
    check not vr.hasErrors
    check config.hooks.entries[0].timeout == DefaultHookTimeout

  test "An explicit timeout wins over the default":
    let (config, vr) = loadFromTomlString(
      """
[[Hook.entries]]
event = "BufWritePost"
command = "true"
timeout = 0
"""
    )
    check not vr.hasErrors
    check config.hooks.entries[0].timeout == 0

  test "Entries keep their order":
    let (config, vr) = loadFromTomlString(
      """
[[Hook.entries]]
event = "BufWritePost"
command = "first"

[[Hook.entries]]
event = "BufWritePost"
command = "second"
"""
    )
    check not vr.hasErrors
    check config.hooks.entries.mapIt(it.command) == @["first", "second"]

  test "A BufWritePre entry takes onFail":
    let (config, vr) = loadFromTomlString(
      """
[[Hook.entries]]
event = "BufWritePre"
command = "gofmt"
onFail = "abort"
"""
    )
    check not vr.hasErrors
    check config.hooks.entries[0].event == heBufWritePre
    check config.hooks.entries[0].onFail == hfaAbort

  test "onFail writes by default":
    let (config, vr) = loadFromTomlString(
      """
[[Hook.entries]]
event = "BufWritePre"
command = "gofmt"
"""
    )
    check not vr.hasErrors
    check config.hooks.entries[0].onFail == hfaWrite

  test "Every event name loads":
    for name in ValidHookEvents:
      let (config, vr) = loadFromTomlString(
        "[[Hook.entries]]\nevent = \"" & name & "\"\ncommand = \"true\"\n"
      )
      check not vr.hasErrors
      check config.hooks.entries.len == 1
      check $config.hooks.entries[0].event == name

suite "Hooks - config validation":
  # An entry is dropped whole rather than loaded half-configured: a hook that
  # fires the wrong command on the wrong files is worse than one that is
  # reported and absent.
  # A template, not a proc: `check` must expand inside the test to fail it.
  template checkRejected(toml: string, badKey: string) =
    let (config, vr) = loadFromTomlString(toml)
    check vr.hasErrors
    check vr.errors.anyIt(it.name.startsWith(badKey))
    check config.hooks.entries.len == 0

  test "Missing event":
    checkRejected("[[Hook.entries]]\ncommand = \"true\"\n", "Hook.entries[0]")

  test "Missing command":
    checkRejected("[[Hook.entries]]\nevent = \"BufWritePost\"\n", "Hook.entries[0]")

  test "onFail on an event the write does not wait for":
    checkRejected(
      "[[Hook.entries]]\nevent = \"BufWritePost\"\ncommand = \"true\"\nonFail = \"abort\"\n",
      "Hook.entries[0].onFail",
    )

  test "showOutput on BufWritePre, whose output is the new text":
    checkRejected(
      "[[Hook.entries]]\nevent = \"BufWritePre\"\ncommand = \"true\"\nshowOutput = true\n",
      "Hook.entries[0].showOutput",
    )

  test "Unknown event":
    checkRejected(
      "[[Hook.entries]]\nevent = \"BufWipeout\"\ncommand = \"true\"\n",
      "Hook.entries[0].event",
    )

  test "Empty command":
    checkRejected(
      "[[Hook.entries]]\nevent = \"BufWritePost\"\ncommand = \"  \"\n",
      "Hook.entries[0].command",
    )

  test "Unknown filetype":
    checkRejected(
      """
[[Hook.entries]]
event = "BufWritePost"
command = "true"
filetype = ["nimrod"]
""",
      "Hook.entries[0].filetype",
    )

  test "Unparsable filter":
    checkRejected(
      """
[[Hook.entries]]
event = "BufWritePost"
command = "true"
filter = "*("
""",
      "Hook.entries[0].filter",
    )

  test "Negative timeout":
    checkRejected(
      """
[[Hook.entries]]
event = "BufWritePost"
command = "true"
timeout = -1
""",
      "Hook.entries[0].timeout",
    )

  test "Negative exitWaitTimeout":
    let (config, vr) = loadFromTomlString("[Hook]\nexitWaitTimeout = -1\n")
    check vr.hasErrors
    check vr.errors.anyIt(it.name == "Hook.exitWaitTimeout")
    check config.hooks.exitWaitTimeout == DefaultHookExitWaitTimeout

  test "A command line whose first token is empty":
    # `''` parses to an empty program name, which has nothing to exec. Caught
    # here rather than at exec time, where a hook that never fires has nowhere
    # to say so.
    checkRejected(
      "[[Hook.entries]]\nevent = \"BufWritePost\"\ncommand = \"'' nph\"\n",
      "Hook.entries[0].command",
    )

  test "An unterminated quote":
    # Left to run to the end of the line, `'${file}` would move into the
    # script of `sh -c`.
    checkRejected(
      "[[Hook.entries]]\nevent = \"BufWritePost\"\ncommand = \"sh -c 'grep x \\\"$1\\\" sh ${file}\"\n",
      "Hook.entries[0].command",
    )
    checkRejected(
      "[[Hook.entries]]\nevent = \"BufWritePost\"\ncommand = \"fmt \\\"${file}\"\n",
      "Hook.entries[0].command",
    )

  test "A wrongly typed key":
    checkRejected(
      """
[[Hook.entries]]
event = "BufWritePost"
command = "true"
showOutput = "yes"
""",
      "Hook.entries[0].showOutput",
    )

  test "An unknown key is reported but keeps the entry":
    let (config, vr) = loadFromTomlString(
      """
[[Hook.entries]]
event = "BufWritePost"
command = "true"
whenever = "always"
"""
    )
    check vr.hasErrors
    check vr.errors.anyIt(it.name == "Hook.entries[0].whenever")
    check config.hooks.entries.len == 1

  test "entries must be an array of tables":
    let (config, vr) = loadFromTomlString("[Hook]\nentries = 1\n")
    check vr.hasErrors
    check config.hooks.entries.len == 0

  test "One bad entry does not drop its neighbours":
    let (config, vr) = loadFromTomlString(
      """
[[Hook.entries]]
event = "BufWritePost"
command = "good"

[[Hook.entries]]
event = "Nonsense"
command = "bad"

[[Hook.entries]]
event = "BufWritePost"
command = "also good"
"""
    )
    check vr.hasErrors
    check config.hooks.entries.mapIt(it.command) == @["good", "also good"]

  test "An unknown [Hook] key is reported":
    let (_, vr) = loadFromTomlString("[Hook]\nenabled = true\n")
    check vr.errors.anyIt(it.name == "Hook.enabled")

suite "Hooks - exCommand":
  proc exEntry(exCommand: string, extra = ""): string =
    ## One BufWritePre entry; `exCommand` goes in a TOML literal string.
    "[[Hook.entries]]\nevent = \"BufWritePre\"\nexCommand = '" & exCommand & "'\n" &
      extra

  template checkRejected(toml: string, badKey: string) =
    let (config, vr) = loadFromTomlString(toml)
    check vr.hasErrors
    check vr.errors.anyIt(it.name.startsWith(badKey))
    check config.hooks.entries.len == 0

  test "stripwhitespace and a :s are read at load":
    let (config, vr) = loadFromTomlString(
      exEntry("stripwhitespace") & "\n" & exEntry(r"%s/\s+$//e") & "\n" &
        exEntry(r":1,$-1s/a/b\~/gIi")
    )
    check not vr.hasErrors
    check config.hooks.entries.len == 3
    check parseHookExCommand(config.hooks.entries[0].exCommand).get.kind ==
      hekStripWhitespace
    let sub = parseHookExCommand(config.hooks.entries[1].exCommand).get
    check sub.kind == hekSubstitute
    check sub.range.kind == erkAll
    check sub.pattern == r"\s+$"
    check sub.replacement == ""
    check sub.flags == "e"
    check parseHookExCommand(config.hooks.entries[2].exCommand).get.replacement == r"b\~"

  test "An exCommand of blanks alone is no Ex command":
    let (config, vr) = loadFromTomlString(
      "[[Hook.entries]]\nevent = \"BufWritePre\"\ncommand = \"fmt\"\nexCommand = ' '\n"
    )
    check not vr.hasErrors
    check config.hooks.entries.len == 1
    check not config.hooks.entries[0].isExHook

  test "A comment after the flags and a `\\=` past the start read":
    let (config, vr) =
      loadFromTomlString(exEntry("%s/a/x\\=y/g \"note") & exEntry("%s/a/\\=/"))
    check vr.errors.len == 1
    check config.hooks.entries.len == 1
    check parseHookExCommand(config.hooks.entries[0].exCommand).get.replacement ==
      "x\\=y"

  for (name, toml, badKey) in [
    (
      "command and exCommand",
      exEntry("stripwhitespace", "command = \"true\"\n"),
      "Hook.entries[0].command",
    ),
    (
      "an empty command with exCommand",
      exEntry("stripwhitespace", "command = \"\"\n"),
      "Hook.entries[0].command",
    ),
    (
      "exCommand on BufWritePost",
      "[[Hook.entries]]\nevent = \"BufWritePost\"\nexCommand = \"stripwhitespace\"\n",
      "Hook.entries[0]",
    ),
    ("a command it does not run", exEntry("write"), "Hook.entries[0].exCommand"),
    ("an unknown command", exEntry("frobnicate"), "Hook.entries[0].exCommand"),
    (
      "stripwhitespace with an argument",
      exEntry("stripwhitespace x"),
      "Hook.entries[0].exCommand",
    ),
    ("stripwhitespace with !", exEntry("stripwhitespace!"), "Hook.entries[0].exCommand"),
    (
      "stripwhitespace with a range",
      exEntry("%stripwhitespace"),
      "Hook.entries[0].exCommand",
    ),
    ("an empty pattern", exEntry("%s//x/"), "Hook.entries[0].exCommand"),
    ("no range", exEntry("s/a/b/"), "Hook.entries[0].exCommand"),
    ("the current line", exEntry(".,$s/a/b/"), "Hook.entries[0].exCommand"),
    ("an offset alone", exEntry("+1s/a/b/"), "Hook.entries[0].exCommand"),
    ("an open start", exEntry(",$s/a/b/"), "Hook.entries[0].exCommand"),
    ("an open end", exEntry("5,s/a/b/"), "Hook.entries[0].exCommand"),
    ("a backwards range", exEntry("10,5s/a/b/"), "Hook.entries[0].exCommand"),
    ("a backwards range from `$`", exEntry("$,$-1s/a/b/"), "Hook.entries[0].exCommand"),
    ("a line below `$`", exEntry("1,$+1s/a/b/"), "Hook.entries[0].exCommand"),
    ("a range ending on line 0", exEntry("1,0s/a/b/"), "Hook.entries[0].exCommand"),
    ("a line above line 0", exEntry("1-2,3s/a/b/"), "Hook.entries[0].exCommand"),
    (
      "an empty exCommand",
      "[[Hook.entries]]\nevent = \"BufWritePre\"\nexCommand = ''\n",
      "Hook.entries[0].exCommand",
    ),
    (
      "a range whose offset overflows",
      exEntry("9223372036854775807+1,1s/a/b/"),
      "Hook.entries[0].exCommand",
    ),
    ("a `~` replacement", exEntry("%s/a/~/"), "Hook.entries[0].exCommand"),
    ("a leading `\\=`", exEntry("%s/a/\\=x/"), "Hook.entries[0].exCommand"),
    ("a regex that does not compile", exEntry("%s/(/x/"), "Hook.entries[0].exCommand"),
    (
      "workingDir",
      exEntry("stripwhitespace", "workingDir = \"/\"\n"),
      "Hook.entries[0].workingDir",
    ),
    ("timeout", exEntry("stripwhitespace", "timeout = 3\n"), "Hook.entries[0].timeout"),
    (
      "onFail",
      exEntry("stripwhitespace", "onFail = \"abort\"\n"),
      "Hook.entries[0].onFail",
    ),
  ]:
    test "Rejected: " & name:
      checkRejected(toml, badKey)

  for flag in ["c", "n", "&", "p", "#", "l", "r", "gc", "cn"]:
    test "Rejected: the flags " & flag:
      checkRejected(exEntry("%s/a/b/" & flag), "Hook.entries[0].exCommand")

  test "Blanks around the command read":
    let (config, vr) =
      loadFromTomlString(exEntry(" %s/a/b/ ") & "\n" & exEntry(" stripwhitespace "))
    check not vr.hasErrors
    check config.hooks.entries.len == 2

  test "Line 0 and lines that only a long file has read":
    let (config, vr) = loadFromTomlString(
      exEntry("0,$s/a/b/") & "\n" & exEntry("0,1s/a/b/") & "\n" &
        exEntry("100,$-5s/a/b/")
    )
    check not vr.hasErrors
    check config.hooks.entries.len == 3

  test "Blanks after a :s with no closing delimiter are its own":
    let (config, vr) =
      loadFromTomlString(exEntry("%s/\\t/    ") & "\n" & exEntry("%s/a /b"))
    check not vr.hasErrors
    check parseHookExCommand(config.hooks.entries[0].exCommand).get.replacement == "    "
    check parseHookExCommand(config.hooks.entries[1].exCommand).get.pattern == "a "

  test "exCommand on another event is the one error":
    let (config, vr) = loadFromTomlString(
      "[[Hook.entries]]\nevent = \"BufWritePost\"\nexCommand = \"stripwhitespace\"\n"
    )
    check vr.errors.len == 1
    check vr.errors[0].name == "Hook.entries[0].exCommand"
    check config.hooks.entries.len == 0

  test "Colons and blanks in front read, as Vim skips them":
    let (config, vr) = loadFromTomlString(
      exEntry(": %s/a/b/") & "\n" & exEntry("::stripwhitespace") & "\n" &
        exEntry(" : :%s/a/b/")
    )
    check not vr.hasErrors
    check config.hooks.entries.len == 3

  test "An exCommand of the wrong type is the one error":
    let (config, vr) =
      loadFromTomlString("[[Hook.entries]]\nevent = \"BufWritePre\"\nexCommand = 5\n")
    check vr.errors.len == 1
    check vr.errors[0].name == "Hook.entries[0].exCommand"
    check config.hooks.entries.len == 0

  test "command and exCommand on another event: only exCommand is refused":
    let (config, vr) = loadFromTomlString(
      "[[Hook.entries]]\nevent = \"BufWritePost\"\ncommand = \"lint\"\n" &
        "exCommand = 'stripwhitespace'\ntimeout = 5\nworkingDir = \"/\"\n"
    )
    check vr.errors.len == 1
    check vr.errors[0].name == "Hook.entries[0].exCommand"
    check config.hooks.entries.len == 0

  test "exCommand makes an Ex hook only on BufWritePre":
    for event in HookEvent:
      checkpoint $event
      let entry = HookEntry(event: event, command: "lint", exCommand: "stripwhitespace")
      check entry.isExHook == (event == heBufWritePre)
      check entry.isProgramHook == (event != heBufWritePre)

  test "An entry built in code with exCommand on another event keeps its command":
    var config = newEditorConfig()
    config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        command: "lint",
        exCommand: "stripwhitespace",
        timeout: DefaultHookTimeout,
      )
    ]
    let path = getTempDir() / "moe_test_hooks_ex_other_event.toml"
    defer:
      removeFile(path)
    check saveConfigToToml(config, path).isOk
    let (reloaded, vr) = loadConfigFromToml(path).get
    check not vr.hasErrors
    check reloaded.hooks.entries.len == 1
    check reloaded.hooks.entries[0].command == "lint"
    check reloaded.hooks.entries[0].exCommand == ""

  test "Command aliases do not change what a hook runs":
    let (config, vr) = loadFromTomlString(
      "[DisabledCommandAliases]\naliases = [\"stripwhitespace\"]\n\n" &
        "[CommandAliases]\nstripwhitespace = { command = \"quit\" }\n\n" &
        exEntry("stripwhitespace")
    )
    check not vr.hasErrors
    check config.hooks.entries.len == 1
    check parseHookExCommand(config.hooks.entries[0].exCommand).get.kind ==
      hekStripWhitespace

  test "An entry with exCommand saves and reloads as it was":
    var config = newEditorConfig()
    config.hooks.entries = @[
      HookEntry(event: heBufWritePre, command: "sort", timeout: 5, onFail: hfaAbort),
      HookEntry(
        event: heBufWritePre,
        exCommand: "%s/\\s+$/\\\\ \"q\"/e",
        filter: r"\.txt$",
        timeout: DefaultHookTimeout,
      ),
    ]
    let path = getTempDir() / "moe_test_hooks_ex_roundtrip.toml"
    defer:
      removeFile(path)
    check saveConfigToToml(config, path).isOk
    let (reloaded, vr) = loadConfigFromToml(path).get
    check not vr.hasErrors
    check reloaded.hooks.entries == config.hooks.entries
    check parseHookExCommand(reloaded.hooks.entries[1].exCommand).isOk

suite "Hooks - config round trip":
  test "Saving and reloading preserves every entry":
    var config = newEditorConfig()
    config.hooks.onAutoSave = true
    config.hooks.exitWaitTimeout = 3
    config.hooks.entries = @[
      HookEntry(
        event: heBufWritePost,
        filetype: @["nim"],
        filter: r"\.nim$",
        command: "nph ${file}",
        workingDir: "/src",
        timeout: 5,
        showOutput: true,
      ),
      HookEntry(event: heBufReadPost, command: "touch ${file}", timeout: 0),
    ]

    let path = getTempDir() / "moe_test_hooks_roundtrip.toml"
    defer:
      removeFile(path)
    check saveConfigToToml(config, path).isOk

    let loaded = loadConfigFromToml(path)
    check loaded.isOk
    let (reloaded, vr) = loaded.get
    check not vr.hasErrors
    check reloaded.hooks.onAutoSave
    check reloaded.hooks.exitWaitTimeout == 3
    check reloaded.hooks.entries == config.hooks.entries

suite "Hooks - unknown events":
  test "An event outside the list is rejected":
    let (config, vr) = loadFromTomlString(
      """
[Hook]
enable = true

[[Hook.entries]]
event = "BufReadPre"
command = "gzip -dc"
"""
    )
    check vr.hasErrors
    check config.hooks.entries.len == 0

suite "Hooks - derived config surface":
  test "The key list comes off the type":
    # Not a list written out beside the type, which could disagree with it.
    let (config, vr) = loadFromTomlString(
      """
[Hook]
enable = true

[[Hook.entries]]
event = "BufWritePost"
command = "make"
typo = 1
"""
    )
    # An unknown key is reported but does not drop the entry.
    check config.hooks.entries.len == 1
    check vr.errors.anyIt("typo" in it.name)

  test "Saving writes every key":
    var config = newEditorConfig()
    config.hooks.entries =
      @[HookEntry(event: heBufWritePost, command: "make", timeout: 60)]

    var lines: seq[string]
    appendHookToml(lines, config.hooks)

    for key in [
      "exitWaitTimeout", "event", "command", "filetype", "filter", "workingDir",
      "timeout", "showOutput",
    ]:
      check lines.anyIt(it.startsWith(key & " = "))

  test "A saved config loads back clean":
    var config = newEditorConfig()
    config.hooks.enable = true
    config.hooks.entries = @[
      HookEntry(event: heBufWritePost, command: "make", timeout: 60),
      HookEntry(event: heBufReadPost, command: "touch ${file}", timeout: 60),
    ]

    let path = getTempDir() / "moe_test_hooks_derived.toml"
    defer:
      removeFile(path)
    check saveConfigToToml(config, path).isOk

    let loaded = loadConfigFromToml(path)
    check loaded.isOk
    let (reloaded, vr) = loaded.get
    check not vr.hasErrors
    check reloaded.hooks.entries == config.hooks.entries
