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

import std/[unittest, os, options, strutils, sequtils]
from std/times import getTime, initDuration, `-`

import pkg/chronos

import ../src/moepkg/quick_run_utils {.all.}
import ../src/moepkg/[config, background_process, child_process]
import ../src/moepkg/buffer/[core, file_io, edit]
import ../src/moepkg/syntax/tokenizer

# Keep the work dirs these tests make out of the user's real cache.
let testCacheHome = getTempDir() / "moe_test_quickrun_cache"
putEnv("XDG_CACHE_HOME", testCacheHome)

template inDir(dir: string, body: untyped) =
  ## Run `body` with `dir` (made fresh) as the current directory.
  removeDir(dir)
  createDir(dir)
  let saved = getCurrentDir()
  setCurrentDir(dir)
  try:
    body
  finally:
    setCurrentDir(saved)
    removeDir(dir)

suite "QuickRunUtils - quickRunStartupMessage":
  test "Generate startup message":
    let msg = quickRunStartupMessage("/path/to/file.nim")
    check msg == "Start QuickRun: /path/to/file.nim..."

  test "Generate startup message with relative path":
    let msg = quickRunStartupMessage("src/main.nim")
    check msg == "Start QuickRun: src/main.nim..."

suite "QuickRunUtils - languageExtension":
  test "Nim extension":
    let result = languageExtension(SourceLanguage.langNim)
    check result.isOk
    check result.get == "nim"

  test "C extension":
    let result = languageExtension(SourceLanguage.langC)
    check result.isOk
    check result.get == "c"

  test "C++ extension":
    let result = languageExtension(SourceLanguage.langCpp)
    check result.isOk
    check result.get == "cpp"

  test "Shell extension":
    let result = languageExtension(SourceLanguage.langShell)
    check result.isOk
    check result.get == "bash"

  test "Python extension":
    let result = languageExtension(SourceLanguage.langPython)
    check result.isOk
    check result.get == "py"

  test "Rust extension":
    let result = languageExtension(SourceLanguage.langRust)
    check result.isOk
    check result.get == "rs"

  test "Unsupported language returns error":
    let result = languageExtension(SourceLanguage.langJava)
    check result.isErr
    check result.error == "Unknown language"

  test "langNone returns error":
    let result = languageExtension(SourceLanguage.langNone)
    check result.isErr

suite "QuickRunUtils - isSh":
  test "Buffer with #!/bin/sh shebang":
    var buffer = newTextBuffer("#!/bin/sh\necho hello")
    check buffer.isSh == true

  test "Buffer with #!/bin/sh shebang and arguments":
    var buffer = newTextBuffer("#!/bin/sh -e\necho hello")
    check buffer.isSh == true

  test "Buffer with #!/usr/bin/env sh shebang":
    var buffer = newTextBuffer("#!/usr/bin/env sh\necho hello")
    check buffer.isSh == true

  test "Buffer with #!/bin/bash shebang":
    var buffer = newTextBuffer("#!/bin/bash\necho hello")
    check buffer.isSh == false

  test "Buffer without shebang":
    var buffer = newTextBuffer("echo hello")
    check buffer.isSh == false

  test "Empty buffer":
    var buffer = newTextBuffer("")
    check buffer.isSh == false

suite "QuickRunUtils - parseShebang":
  test "Empty buffer returns none":
    var buffer = newTextBuffer("")
    check buffer.parseShebang.isNone

  test "Buffer without shebang returns none":
    var buffer = newTextBuffer("echo hello")
    check buffer.parseShebang.isNone

  test "Shebang with only #! returns none":
    var buffer = newTextBuffer("#!\necho hello")
    check buffer.parseShebang.isNone

  test "Direct interpreter path":
    var buffer = newTextBuffer("#!/bin/bash\necho hello")
    let r = buffer.parseShebang
    check r.isSome
    check r.get.cmd == "/bin/bash"
    check r.get.args.len == 0

  test "Direct interpreter with args":
    var buffer = newTextBuffer("#!/bin/bash -x\necho hello")
    let r = buffer.parseShebang
    check r.isSome
    check r.get.cmd == "/bin/bash"
    check r.get.args == @["-x"]

  test "env-style python3":
    var buffer = newTextBuffer("#!/usr/bin/env python3\nprint('x')")
    let r = buffer.parseShebang
    check r.isSome
    check r.get.cmd == "python3"
    check r.get.args.len == 0

  test "env-style with args":
    var buffer = newTextBuffer("#!/usr/bin/env python3 -u\nprint('x')")
    let r = buffer.parseShebang
    check r.isSome
    check r.get.cmd == "python3"
    check r.get.args == @["-u"]

  test "env-style with only env returns none-ish (env alone)":
    # "#!/usr/bin/env" with no following command should be treated as no shebang
    var buffer = newTextBuffer("#!/usr/bin/env\n")
    let r = buffer.parseShebang
    check r.isSome
    check r.get.cmd == "/usr/bin/env"

  test "Shebang with leading spaces":
    var buffer = newTextBuffer("#!   /bin/sh\necho hello")
    let r = buffer.parseShebang
    check r.isSome
    check r.get.cmd == "/bin/sh"

  test "perl interpreter":
    var buffer = newTextBuffer("#!/usr/bin/perl\nprint \"hi\\n\";")
    let r = buffer.parseShebang
    check r.isSome
    check r.get.cmd == "/usr/bin/perl"

  test "Shebang with only whitespace returns none":
    var buffer = newTextBuffer("#!   \t  \necho hello")
    check buffer.parseShebang.isNone

  test "Shebang with shell metachars is passed as opaque argv (no injection)":
    # startProcess uses fork+exec (no shell), so these characters end up as
    # literal bytes in the command name — they cannot inject commands.
    var buffer = newTextBuffer("#!/bin/sh; rm -rf /\n")
    let r = buffer.parseShebang
    check r.isSome
    # The whole token is taken verbatim as cmd; whitespace is the only splitter.
    check r.get.cmd == "/bin/sh;"
    check r.get.args == @["rm", "-rf", "/"]

  test "Shebang with command substitution is passed verbatim":
    var buffer = newTextBuffer("#!$(rm -rf /)\n")
    let r = buffer.parseShebang
    check r.isSome
    check r.get.cmd == "$(rm"

  test "Shebang with backticks is passed verbatim":
    var buffer = newTextBuffer("#!`rm -rf /`\n")
    let r = buffer.parseShebang
    check r.isSome
    check r.get.cmd == "`rm"

  test "Relative interpreter name (PATH lookup)":
    var buffer = newTextBuffer("#!python3\nprint('x')\n")
    let r = buffer.parseShebang
    check r.isSome
    check r.get.cmd == "python3"

  test "env with no interpreter falls back to /usr/bin/env itself":
    # Documented behaviour: a lone "/usr/bin/env" shebang is rare but valid in
    # the sense that it gets executed as the command.
    var buffer = newTextBuffer("#!/usr/bin/env\n")
    let r = buffer.parseShebang
    check r.isSome
    check r.get.cmd == "/usr/bin/env"
    check r.get.args.len == 0

suite "QuickRunUtils - nimQuickRunCommand":
  test "Basic nim command":
    let settings =
      QuickRunConfig(nimAdvancedCommand: none(string), nimOptions: none(string))
    let cmd = nimQuickRunCommand("/path/to/file.nim", settings)
    check cmd.cmd == "nim"
    check cmd.args == @["c", "-r", "/path/to/file.nim"]

  test "Nim command with advanced command":
    let settings =
      QuickRunConfig(nimAdvancedCommand: some("js"), nimOptions: none(string))
    let cmd = nimQuickRunCommand("/path/to/file.nim", settings)
    check cmd.cmd == "nim"
    check cmd.args == @["js", "-r", "/path/to/file.nim"]

  test "Nim command with options":
    let settings =
      QuickRunConfig(nimAdvancedCommand: none(string), nimOptions: some("-d:release"))
    let cmd = nimQuickRunCommand("/path/to/file.nim", settings)
    check cmd.cmd == "nim"
    check cmd.args == @["c", "-r", "-d:release", "/path/to/file.nim"]

  test "Nim command with advanced command and options":
    let settings =
      QuickRunConfig(nimAdvancedCommand: some("cpp"), nimOptions: some("-d:danger"))
    let cmd = nimQuickRunCommand("/path/to/file.nim", settings)
    check cmd.cmd == "nim"
    check cmd.args == @["cpp", "-r", "-d:danger", "/path/to/file.nim"]

suite "QuickRunUtils - clangQuickRunCommand":
  test "Basic C command":
    let settings = QuickRunConfig(clangOptions: none(string))
    let cmd = clangQuickRunCommand("/path/to/file.c", "/work/file", settings)
    check cmd.cmd == "/bin/bash"
    check cmd.args.len == 2
    check cmd.args[0] == "-c"
    check cmd.args[1] == "gcc /path/to/file.c -o /work/file && /work/file"

  test "C command with options":
    let settings = QuickRunConfig(clangOptions: some("-Wall -Wextra"))
    let cmd = clangQuickRunCommand("/path/to/file.c", "/work/file", settings)
    check cmd.cmd == "/bin/bash"
    check "-Wall -Wextra" in cmd.args[1]

suite "QuickRunUtils - cppQuickRunCommand":
  test "Basic C++ command":
    let settings = QuickRunConfig(cppOptions: none(string))
    let cmd = cppQuickRunCommand("/path/to/file.cpp", "/work/file", settings)
    check cmd.cmd == "/bin/bash"
    check cmd.args.len == 2
    check cmd.args[0] == "-c"
    check cmd.args[1] == "g++ /path/to/file.cpp -o /work/file && /work/file"

  test "C++ command with options":
    let settings = QuickRunConfig(cppOptions: some("-std=c++17"))
    let cmd = cppQuickRunCommand("/path/to/file.cpp", "/work/file", settings)
    check cmd.cmd == "/bin/bash"
    check "-std=c++17" in cmd.args[1]

suite "QuickRunUtils - shQuickRunCommand":
  test "Basic sh command":
    let settings = QuickRunConfig(shOptions: none(string))
    let cmd = shQuickRunCommand("/path/to/script.sh", settings)
    check cmd.cmd == "/bin/sh"
    check cmd.args == @["/path/to/script.sh"]

  test "sh command with options":
    let settings = QuickRunConfig(shOptions: some("-x"))
    let cmd = shQuickRunCommand("/path/to/script.sh", settings)
    check cmd.cmd == "/bin/sh"
    check cmd.args == @["-x", "/path/to/script.sh"]

suite "QuickRunUtils - bashQuickRunCommand":
  test "Basic bash command":
    let settings = QuickRunConfig(bashOptions: none(string))
    let cmd = bashQuickRunCommand("/path/to/script.sh", settings)
    check cmd.cmd == "/bin/bash"
    check cmd.args == @["/path/to/script.sh"]

  test "bash command with options":
    let settings = QuickRunConfig(bashOptions: some("-x"))
    let cmd = bashQuickRunCommand("/path/to/script.sh", settings)
    check cmd.cmd == "/bin/bash"
    check cmd.args == @["-x", "/path/to/script.sh"]

suite "QuickRunUtils - pythonQuickRunCommand":
  test "Basic python command":
    let settings = QuickRunConfig()
    let cmd = pythonQuickRunCommand("/path/to/script.py", settings)
    check cmd.cmd == "python3"
    check cmd.args == @["/path/to/script.py"]

suite "QuickRunUtils - rustQuickRunCommand":
  test "Basic rust command":
    let settings = QuickRunConfig()
    let cmd = rustQuickRunCommand("/path/to/file.rs", "/work/file", settings)
    check cmd.cmd == "/bin/bash"
    check cmd.args.len == 2
    check cmd.args[0] == "-c"
    check cmd.args[1] == "rustc /path/to/file.rs -o /work/file && /work/file"

suite "QuickRunUtils - programPath":
  test "The program is named after the source, inside the work dir":
    check programPath("/work", "/some/deep/path/myprogram.rs") == "/work/myprogram"
    check programPath("/work", "main.c") == "/work/main"

suite "QuickRunUtils - command injection (H11 regression)":
  # A malicious file/dir name must not be able to inject shell commands into the
  # `/bin/bash -c` string used by the C/C++/Rust runners. Every file-derived
  # value is passed through quoteShell, so `$(...)`/backticks/`;` stay inert.
  test "C: malicious file name is shell-quoted":
    let settings = QuickRunConfig(clangOptions: none(string))
    let malicious = "/tmp/evil$(touch pwned).c"
    let program = programPath("/work", malicious)
    let cmd = clangQuickRunCommand(malicious, program, settings)
    check quoteShell(malicious) in cmd.args[1]
    check quoteShell(program) in cmd.args[1]
    # The raw, unquoted name must not appear right after the compiler.
    check ("gcc " & malicious) notin cmd.args[1]

  test "C++: malicious file name is shell-quoted":
    let settings = QuickRunConfig(cppOptions: none(string))
    let malicious = "/tmp/evil`id`.cpp"
    let program = programPath("/work", malicious)
    let cmd = cppQuickRunCommand(malicious, program, settings)
    check quoteShell(malicious) in cmd.args[1]
    check quoteShell(program) in cmd.args[1]
    check ("g++ " & malicious) notin cmd.args[1]

  test "Rust: malicious name is quoted in both compile and run":
    let settings = QuickRunConfig()
    let malicious = "/tmp/ev il$(id).rs"
    let program = programPath("/work dir", malicious)
    let cmd = rustQuickRunCommand(malicious, program, settings)
    check quoteShell(malicious) in cmd.args[1]
    # The program path is used both for `-o` and to execute it.
    check cmd.args[1].count(quoteShell(program)) == 2
    check "$(id)" notin
      cmd.args[1].replace(quoteShell(malicious), "").replace(quoteShell(program), "")

suite "QuickRunUtils - quickRunCommand":
  test "Nim language":
    var buffer = newTextBuffer("echo \"hello\"")
    buffer.language = SourceLanguage.langNim
    let settings =
      QuickRunConfig(nimAdvancedCommand: none(string), nimOptions: none(string))
    let result = quickRunCommand(
      "/path/to/file.nim", SourceLanguage.langNim, buffer, settings, "/work"
    )
    check result.isOk
    check result.get.cmd == "nim"

  test "C language":
    var buffer = newTextBuffer("#include <stdio.h>\nint main() { return 0; }")
    buffer.language = SourceLanguage.langC
    let settings = QuickRunConfig(clangOptions: none(string))
    let result = quickRunCommand(
      "/path/to/file.c", SourceLanguage.langC, buffer, settings, "/work"
    )
    check result.isOk
    check result.get.cmd == "/bin/bash"
    check "gcc" in result.get.args[1]

  test "C++ language":
    var buffer = newTextBuffer("#include <iostream>\nint main() { return 0; }")
    buffer.language = SourceLanguage.langCpp
    let settings = QuickRunConfig(cppOptions: none(string))
    let result = quickRunCommand(
      "/path/to/file.cpp", SourceLanguage.langCpp, buffer, settings, "/work"
    )
    check result.isOk
    check result.get.cmd == "/bin/bash"
    check "g++" in result.get.args[1]

  test "Rust language":
    var buffer = newTextBuffer("fn main() {}")
    buffer.language = SourceLanguage.langRust
    let settings = QuickRunConfig()
    let result = quickRunCommand(
      "/path/to/file.rs", SourceLanguage.langRust, buffer, settings, "/work"
    )
    check result.isOk
    check result.get.cmd == "/bin/bash"
    check "rustc" in result.get.args[1]

  test "Python language":
    var buffer = newTextBuffer("print('hello')")
    buffer.language = SourceLanguage.langPython
    let settings = QuickRunConfig()
    let result = quickRunCommand(
      "/path/to/script.py", SourceLanguage.langPython, buffer, settings, "/work"
    )
    check result.isOk
    check result.get.cmd == "python3"

  test "Shell language with sh shebang":
    var buffer = newTextBuffer("#!/bin/sh\necho hello")
    buffer.language = SourceLanguage.langShell
    let settings = QuickRunConfig(shOptions: none(string), bashOptions: none(string))
    let result = quickRunCommand(
      "/path/to/script.sh", SourceLanguage.langShell, buffer, settings, "/work"
    )
    check result.isOk
    check result.get.cmd == "/bin/sh"

  test "Shell language with bash shebang":
    var buffer = newTextBuffer("#!/bin/bash\necho hello")
    buffer.language = SourceLanguage.langShell
    let settings = QuickRunConfig(shOptions: none(string), bashOptions: none(string))
    let result = quickRunCommand(
      "/path/to/script.sh", SourceLanguage.langShell, buffer, settings, "/work"
    )
    check result.isOk
    check result.get.cmd == "/bin/bash"

  test "Unsupported language returns error":
    var buffer = newTextBuffer("<html></html>")
    buffer.language = SourceLanguage.langHtml
    let settings = QuickRunConfig()
    let result = quickRunCommand(
      "/path/to/file.html", SourceLanguage.langHtml, buffer, settings, "/work"
    )
    check result.isErr
    check "Unsupported language" in result.error

  test "Unsupported language falls back to shebang (python via env)":
    var buffer = newTextBuffer("#!/usr/bin/env python3\nprint('x')")
    buffer.language = SourceLanguage.langNone
    let settings = QuickRunConfig()
    let result = quickRunCommand(
      "/path/to/script", SourceLanguage.langNone, buffer, settings, "/work"
    )
    check result.isOk
    check result.get.cmd == "python3"
    check result.get.args == @["/path/to/script"]

  test "Unsupported language falls back to shebang (perl direct)":
    var buffer = newTextBuffer("#!/usr/bin/perl -w\nprint \"x\\n\";")
    buffer.language = SourceLanguage.langNone
    let settings = QuickRunConfig()
    let result = quickRunCommand(
      "/path/to/script.pl", SourceLanguage.langNone, buffer, settings, "/work"
    )
    check result.isOk
    check result.get.cmd == "/usr/bin/perl"
    check result.get.args == @["-w", "/path/to/script.pl"]

  test "Unsupported language without shebang still errors":
    var buffer = newTextBuffer("just text")
    buffer.language = SourceLanguage.langNone
    let settings = QuickRunConfig()
    let result = quickRunCommand(
      "/path/to/file", SourceLanguage.langNone, buffer, settings, "/work"
    )
    check result.isErr
    check "Unsupported language" in result.error

proc runToEnd(prepared: QuickRunPrepareResult): seq[string] =
  ## Start `prepared`, wait for it, and return its output.
  let started = startBackgroundQuickRun(prepared)
  doAssert started.isOk, started.error
  let output = waitFor started.get.waitForResultAsync(60.seconds)
  doAssert output.isOk, output.error
  output.get

suite "QuickRunUtils - createWorkDir":
  test "An empty XDG_CACHE_HOME falls back to $HOME/.cache":
    # `getCacheDir` returns "" for a set-but-empty XDG_CACHE_HOME, though the
    # XDG spec treats it as unset.
    let home = getTempDir() / "moe_test_quickrun_home"
    removeDir(home)
    createDir(home)
    defer:
      removeDir(home)

    let
      savedCache = getEnv("XDG_CACHE_HOME")
      savedHome = getEnv("HOME")
    putEnv("XDG_CACHE_HOME", "")
    putEnv("HOME", home)
    try:
      let created = createWorkDir()
      require created.isOk
      defer:
        removeQuickRunWorkDir(created.get)
      check created.get.parentDir == home / ".cache" / "moe" / "quickrun"
    finally:
      if savedCache.len > 0:
        putEnv("XDG_CACHE_HOME", savedCache)
      else:
        delEnv("XDG_CACHE_HOME")
      if savedHome.len > 0:
        putEnv("HOME", savedHome)
      else:
        delEnv("HOME")

suite "QuickRunUtils - prepareQuickRun":
  test "Prepare QuickRun for Nim file with path":
    var buffer = newTextBuffer("echo \"hello\"", some(getTempDir() / "test.nim"))
    buffer.language = SourceLanguage.langNim

    # Create temp file
    writeFile(getTempDir() / "test.nim", "echo \"hello\"")
    # Stamped like a real load: the write gate refuses a file no one read.
    buffer.noteFileStamp(getTempDir() / "test.nim")
    defer:
      removeFile(getTempDir() / "test.nim")

    let config = newEditorConfig()
    let result = prepareQuickRun(buffer, config)
    check result.isOk
    check result.get.filePath == getTempDir() / "test.nim"
    # Nim leaves its program next to the source: nothing for QuickRun to hold.
    check result.get.workDir == ""
    check result.get.command.cmd == "nim"

  test "Prepare QuickRun for unsaved buffer creates temp file":
    var buffer = newTextBuffer("print('hello')")
    buffer.language = SourceLanguage.langPython

    var config = newEditorConfig()
    config.quickRun.saveBufferWhenQuickRun = true

    let result = prepareQuickRun(buffer, config)
    require result.isOk
    defer:
      removeQuickRunWorkDir(result.get.workDir)
    check result.get.workDir.len > 0
    check result.get.filePath == result.get.workDir / "quickruntemp.py"
    check result.get.command.cmd == "python3"
    check result.get.command.args == @[result.get.filePath]
    # A temp copy only: no save, nothing owed.
    check result.get.didSave == false

  test "The temp copy leaves an unsaved buffer unsaved and unnamed":
    # saveFile would bind the buffer to a path QuickRun deletes after the run.
    var buffer = newTextBuffer("print('hello')")
    buffer.language = SourceLanguage.langPython
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "#")

    var config = newEditorConfig()
    config.quickRun.saveBufferWhenQuickRun = true

    let result = prepareQuickRun(buffer, config)
    require result.isOk
    defer:
      removeQuickRunWorkDir(result.get.workDir)

    check buffer.filePath.isNone
    check buffer.isModified
    check readFile(result.get.filePath) == buffer.getFileContent

  test "The work dir is private and under the user's cache":
    # Not the shared temp dir: nim runs any `config.nims` found in a parent of
    # the source, and anyone can put one in /tmp.
    var buffer = newTextBuffer("print('hello')")
    buffer.language = SourceLanguage.langPython

    let result = prepareQuickRun(buffer, newEditorConfig())
    require result.isOk
    defer:
      removeQuickRunWorkDir(result.get.workDir)
    check result.get.workDir.parentDir == testCacheHome / "moe" / "quickrun"
    when defined(posix):
      check getFilePermissions(result.get.workDir) ==
        {fpUserRead, fpUserWrite, fpUserExec}

  test "Each run gets its own work dir":
    var buffer = newTextBuffer("print('hello')")
    buffer.language = SourceLanguage.langPython

    let
      first = prepareQuickRun(buffer, newEditorConfig())
      second = prepareQuickRun(buffer, newEditorConfig())
    require first.isOk and second.isOk
    defer:
      removeQuickRunWorkDir(first.get.workDir)
      removeQuickRunWorkDir(second.get.workDir)
    check first.get.workDir != second.get.workDir

  test "Staging an unsaved buffer writes nothing to the current directory":
    # A planted `quickruntemp.<ext>` symlink used to be followed and written
    # through.
    let victim = getTempDir() / "moe_test_quickrun_victim.txt"
    writeFile(victim, "precious")
    defer:
      removeFile(victim)

    inDir(getTempDir() / "moe_test_quickrun_cwd_stage"):
      createSymlink(victim, "quickruntemp.py")
      var buffer = newTextBuffer("print('hello')")
      buffer.language = SourceLanguage.langPython

      let result = prepareQuickRun(buffer, newEditorConfig())
      require result.isOk
      defer:
        removeQuickRunWorkDir(result.get.workDir)
      check readFile(victim) == "precious"
      var entries: seq[string]
      for _, path in walkDir("."):
        entries.add path.extractFilename
      check entries == @["quickruntemp.py"]

  test "A real C file builds into the work dir":
    let path = getTempDir() / "moe_test_quickrun_real.c"
    writeFile(path, "int main() { return 0; }\n")
    defer:
      removeFile(path)

    var buffer = newTextBuffer()
    discard buffer.loadFile(path)
    buffer.language = SourceLanguage.langC

    let result = prepareQuickRun(buffer, newEditorConfig())
    require result.isOk
    defer:
      removeQuickRunWorkDir(result.get.workDir)
    check result.get.filePath == path
    check result.get.workDir.len > 0
    let program = quoteShell(result.get.workDir / "moe_test_quickrun_real")
    check ("-o " & program & " && " & program) in result.get.command.args[1]

  test "Prepare QuickRun for unsupported language returns error":
    var buffer = newTextBuffer("<html></html>")
    buffer.language = SourceLanguage.langHtml

    let config = newEditorConfig()
    let result = prepareQuickRun(buffer, config)
    check result.isErr
    check "Unknown language" in result.error or "Unsupported language" in result.error

  test "Prepare QuickRun with saveBufferWhenQuickRun disabled":
    var buffer = newTextBuffer("echo \"hello\"", some(getTempDir() / "test_nosave.nim"))
    buffer.language = SourceLanguage.langNim

    # Create file first
    writeFile(getTempDir() / "test_nosave.nim", "echo \"original\"")
    defer:
      removeFile(getTempDir() / "test_nosave.nim")

    var config = newEditorConfig()
    config.quickRun.saveBufferWhenQuickRun = false

    let result = prepareQuickRun(buffer, config)
    check result.isOk
    check result.get.filePath == getTempDir() / "test_nosave.nim"
    check result.get.workDir == ""
    # Saving disabled: no save, nothing owed.
    check result.get.didSave == false

  test "Prepare QuickRun refuses to overwrite an externally modified file":
    let path = getTempDir() / "test_quickrun_ext_mod.nim"
    writeFile(path, "echo \"original\"")
    defer:
      removeFile(path)

    var buffer = newTextBuffer()
    discard buffer.loadFile(path)
    buffer.language = SourceLanguage.langNim

    # Simulate external modification after load.
    buffer.applyFileStamp(presentStamp(getTime() - initDuration(seconds = 2), 0))
    writeFile(path, "echo \"external change\"")

    let config = newEditorConfig()
    let result = prepareQuickRun(buffer, config)
    check result.isErr
    check "Failed to save" in result.error
    # On-disk content must be left untouched.
    check readFile(path) == "echo \"external change\""

  test "A refused save removes the work dir it made":
    let path = getTempDir() / "test_quickrun_ext_mod.c"
    writeFile(path, "int main() { return 0; }\n")
    defer:
      removeFile(path)

    var buffer = newTextBuffer()
    discard buffer.loadFile(path)
    buffer.language = SourceLanguage.langC
    buffer.applyFileStamp(presentStamp(getTime() - initDuration(seconds = 2), 0))
    writeFile(path, "int main() { return 1; }\n")

    let before = toSeq(walkDir(testCacheHome / "moe" / "quickrun")).len
    let result = prepareQuickRun(buffer, newEditorConfig())
    check result.isErr
    check toSeq(walkDir(testCacheHome / "moe" / "quickrun")).len == before

  test "Prepare QuickRun saves an unsaved edit when not externally modified":
    let path = getTempDir() / "test_quickrun_ok.nim"
    writeFile(path, "echo \"original\"")
    defer:
      removeFile(path)

    var buffer = newTextBuffer()
    discard buffer.loadFile(path)
    buffer.language = SourceLanguage.langNim
    # Simulate an unsaved edit; the file on disk keeps its original mtime.
    discard buffer.insert(1, "echo \"edited\"")

    let config = newEditorConfig()
    let result = prepareQuickRun(buffer, config)
    check result.isOk
    check result.get.filePath == path
    # The unsaved edit must have been written to disk.
    check "echo \"edited\"" in readFile(path)
    # A real save was made, so the caller owes it what every write owes.
    check result.get.didSave == true

  test "Prepare QuickRun with an unrunnable language writes nothing":
    # Assembly runs before any disk write: assembly failure must leave no
    # bytes behind and owe no post-write effects.
    let path = getTempDir() / "test_quickrun_unsupported.html"
    writeFile(path, "<html>original</html>")
    defer:
      removeFile(path)

    var buffer = newTextBuffer()
    discard buffer.loadFile(path)
    buffer.language = SourceLanguage.langHtml
    discard buffer.insert(1, "<!-- edited -->")

    var config = newEditorConfig()
    config.quickRun.saveBufferWhenQuickRun = true

    let result = prepareQuickRun(buffer, config)
    check result.isErr
    check "Unsupported language" in result.error
    # Nothing written: disk keeps the original, the buffer keeps its edit.
    check readFile(path) == "<html>original</html>"
    check buffer.isModified

  test "Prepare QuickRun with nonexistent file path uses temp file":
    var buffer = newTextBuffer("echo \"hello\"", some("/nonexistent/path/file.nim"))
    buffer.language = SourceLanguage.langNim

    let config = newEditorConfig()
    let result = prepareQuickRun(buffer, config)
    require result.isOk
    defer:
      removeQuickRunWorkDir(result.get.workDir)
    check result.get.filePath == result.get.workDir / "quickruntemp.nim"

  test "Prepare QuickRun for unsupported language with no filePath":
    var buffer = newTextBuffer("unsupported content")
    buffer.language = SourceLanguage.langMarkdown

    let config = newEditorConfig()
    let result = prepareQuickRun(buffer, config)
    check result.isErr
    check "Unknown language" in result.error

  test "Prepare QuickRun for each supported language temp file":
    for (text, lang, name) in [
      ("echo 1", SourceLanguage.langNim, "quickruntemp.nim"),
      ("int main() { return 0; }", SourceLanguage.langC, "quickruntemp.c"),
      ("int main() { return 0; }", SourceLanguage.langCpp, "quickruntemp.cpp"),
      ("echo hello", SourceLanguage.langShell, "quickruntemp.bash"),
      ("#!/bin/sh\necho hello", SourceLanguage.langShell, "quickruntemp.sh"),
      ("#!/bin/sh -e\necho hello", SourceLanguage.langShell, "quickruntemp.sh"),
      ("fn main() {}", SourceLanguage.langRust, "quickruntemp.rs"),
    ]:
      var buffer = newTextBuffer(text)
      buffer.language = lang
      let result = prepareQuickRun(buffer, newEditorConfig())
      require result.isOk
      check result.get.filePath == result.get.workDir / name
      check fileExists(result.get.filePath)
      removeQuickRunWorkDir(result.get.workDir)

suite "QuickRunUtils - startBackgroundQuickRun":
  test "Start QuickRun with echo command":
    proc runTest(): Future[tuple[isOk: bool, output: seq[string]]] {.async.} =
      let prepared = QuickRunPrepareResult(
        command: BackgroundProcessCommand(
          cmd: "echo", args: @["quick", "run"], workingDir: getCurrentDir()
        ),
        filePath: "test.nim",
        didSave: false,
      )

      let r = startBackgroundQuickRun(prepared)
      if r.isOk:
        let qp = r.get
        let output = await qp.waitForResultAsync(30.seconds)
        if output.isOk:
          return (true, output.get)
        else:
          return (false, @[])
      else:
        return (false, @[])

    let r = waitFor runTest()
    check r.isOk
    check r.output.len >= 1
    check r.output[0] == "quick run"

  test "Start QuickRun with invalid command returns error":
    proc runTest(): Future[bool] {.async.} =
      let prepared = QuickRunPrepareResult(
        command: BackgroundProcessCommand(
          cmd: "/nonexistent/command", args: @[], workingDir: getCurrentDir()
        ),
        filePath: "test.nim",
        didSave: false,
      )

      let r = startBackgroundQuickRun(prepared)
      return r.isErr

    check waitFor(runTest())

  test "Failed start removes the work dir":
    let workDir = createWorkDir().get
    writeFile(workDir / "quickruntemp.py", "print('leaked?')")

    let prepared = QuickRunPrepareResult(
      command: BackgroundProcessCommand(
        cmd: "/nonexistent/command", args: @[], workingDir: getCurrentDir()
      ),
      filePath: workDir / "quickruntemp.py",
      workDir: workDir,
    )
    check startBackgroundQuickRun(prepared).isErr
    check not dirExists(workDir)

  test "Failed start without a work dir removes nothing":
    let keepPath = getTempDir() / "moe_test_quickrun_start_fail_keep.nim"
    writeFile(keepPath, "echo 1")
    defer:
      removeFile(keepPath)

    let prepared = QuickRunPrepareResult(
      command: BackgroundProcessCommand(
        cmd: "/nonexistent/command", args: @[], workingDir: getCurrentDir()
      ),
      filePath: keepPath,
    )
    check startBackgroundQuickRun(prepared).isErr
    check fileExists(keepPath)

suite "QuickRunUtils - waitForResultAsync":
  test "Wait for process and get output":
    proc runTest(): Future[tuple[isOk: bool, output: seq[string]]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "echo", args: @["hello", "world"], workingDir: getCurrentDir()
      )

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let qp = QuickRunProcess(command: cmd, filePath: "test.nim", process: r.get)
        let output = await qp.waitForResultAsync(30.seconds)
        if output.isOk:
          return (true, output.get)
        else:
          return (false, @[])
      else:
        return (false, @[])

    let r = waitFor runTest()
    check r.isOk
    check r.output.len >= 1
    check r.output[0] == "hello world"

  test "Wait for multi-line output":
    proc runTest(): Future[seq[string]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "sh",
        args: @["-c", "echo line1; echo line2; echo line3"],
        workingDir: getCurrentDir(),
      )

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let qp = QuickRunProcess(command: cmd, filePath: "test.sh", process: r.get)
        let output = await qp.waitForResultAsync(30.seconds)
        if output.isOk:
          return output.get
        else:
          return @[]
      else:
        return @[]

    let output = waitFor runTest()
    check output.len >= 3
    check output[0] == "line1"
    check output[1] == "line2"
    check output[2] == "line3"

suite "QuickRunUtils - work dir removal":
  test "The work dir goes when the run ends":
    let workDir = createWorkDir().get
    writeFile(workDir / "quickruntemp.c", "int main() { return 0; }")
    writeFile(workDir / "quickruntemp", "fake executable")

    let cmd = BackgroundProcessCommand(
      cmd: "echo", args: @["test"], workingDir: getCurrentDir()
    )
    let r = startBackgroundProcess(cmd)
    require r.isOk
    let qp = QuickRunProcess(
      command: cmd,
      filePath: workDir / "quickruntemp.c",
      workDir: workDir,
      process: r.get,
    )
    discard waitFor qp.waitForResultAsync(30.seconds)
    check not dirExists(workDir)

  test "A run without a work dir leaves its file alone":
    let path = getTempDir() / "moe_test_quickrun_no_cleanup.nim"
    writeFile(path, "echo \"test\"")
    defer:
      removeFile(path)

    let cmd = BackgroundProcessCommand(
      cmd: "echo", args: @["test"], workingDir: getCurrentDir()
    )
    let r = startBackgroundProcess(cmd)
    require r.isOk
    let qp = QuickRunProcess(command: cmd, filePath: path, process: r.get)
    discard waitFor qp.waitForResultAsync(30.seconds)
    check fileExists(path)

suite "QuickRunUtils - runs leave the current directory alone":
  test "An unsaved bash buffer runs from the work dir":
    let victim = getTempDir() / "moe_test_quickrun_bash_victim.txt"
    writeFile(victim, "precious")
    defer:
      removeFile(victim)

    inDir(getTempDir() / "moe_test_quickrun_cwd_bash"):
      createSymlink(victim, "quickruntemp.bash")
      var buffer = newTextBuffer("echo hi\npwd")
      buffer.language = SourceLanguage.langShell

      let prepared = prepareQuickRun(buffer, newEditorConfig())
      require prepared.isOk
      let output = runToEnd(prepared.get)
      check output.len == 2
      check output[0] == "hi"
      # The program still runs where the editor does.
      check output[1] == getCurrentDir()
      check readFile(victim) == "precious"
      check symlinkExists("quickruntemp.bash")
      check not dirExists(prepared.get.workDir)

  test "A real C file keeps the user's .out and leaves no program behind":
    if findExe("gcc").len == 0:
      skip()
    else:
      inDir(getTempDir() / "moe_test_quickrun_cwd_c"):
        writeFile(".out", "user data")
        let path = getCurrentDir() / "hello.c"
        writeFile(
          path, "#include <stdio.h>\nint main() { puts(\"hello\"); return 0; }\n"
        )

        var buffer = newTextBuffer()
        discard buffer.loadFile(path)
        buffer.language = SourceLanguage.langC

        let prepared = prepareQuickRun(buffer, newEditorConfig())
        require prepared.isOk
        check runToEnd(prepared.get) == @["hello"]
        check readFile(".out") == "user data"
        check not fileExists("hello")
        check not dirExists(prepared.get.workDir)

suite "QuickRunUtils - cancel and kill":
  test "Cancel running process":
    proc runTest(): Future[bool] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "sleep", args: @["10"], workingDir: getCurrentDir()
      )

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let qp = QuickRunProcess(command: cmd, filePath: "test.sh", process: r.get)
        qp.cancel()
        await sleepAsync(100.milliseconds)
        let finished = not qp.process.process.running()
        return finished
      else:
        return false

    let finished = waitFor runTest()
    check finished

  test "Kill running process":
    proc runTest(): Future[bool] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "sleep", args: @["10"], workingDir: getCurrentDir()
      )

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let qp = QuickRunProcess(command: cmd, filePath: "test.sh", process: r.get)
        qp.kill()
        await sleepAsync(100.milliseconds)
        let finished = not qp.process.process.running()
        return finished
      else:
        return false

    let finished = waitFor runTest()
    check finished

suite "QuickRunUtils - abandonQuickRunProcess":
  test "Removes the work dir":
    let workDir = createWorkDir().get
    writeFile(workDir / "quickruntemp.py", "print(1)")
    # nil process: kill() is a no-op, so this exercises the removal only.
    let p = QuickRunProcess(filePath: workDir / "quickruntemp.py", workDir: workDir)
    abandonQuickRunProcess(p)
    check not dirExists(workDir)

  test "Leaves the file alone without a work dir":
    let path = getTempDir() / "moe_test_quickrun_keep.txt"
    writeFile(path, "echo 1")
    let p = QuickRunProcess(filePath: path)
    abandonQuickRunProcess(p)
    check fileExists(path)
    removeFile(path)

  test "Safe to call multiple times":
    let workDir = createWorkDir().get
    let p = QuickRunProcess(filePath: workDir / "quickruntemp.py", workDir: workDir)
    abandonQuickRunProcess(p)
    abandonQuickRunProcess(p)
    check not dirExists(workDir)

  test "Kills a running process and removes the work dir":
    proc runTest(): Future[bool] {.async.} =
      let workDir = createWorkDir().get
      let cmd = BackgroundProcessCommand(
        cmd: "sleep", args: @["10"], workingDir: getCurrentDir()
      )
      let r = startBackgroundProcess(cmd)
      if not r.isOk:
        return false
      let qp = QuickRunProcess(
        command: cmd,
        filePath: workDir / "quickruntemp.sh",
        workDir: workDir,
        process: r.get,
      )
      abandonQuickRunProcess(qp)
      await sleepAsync(100.milliseconds)
      return not qp.process.process.running() and not dirExists(workDir)

    check waitFor runTest()
