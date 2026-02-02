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

import std/[unittest, os, options, strutils]

import pkg/chronos

import ../src/moepkg/quickrunutils {.all.}
import ../src/moepkg/[config, buffer, backgroundprocess]
import ../src/moepkg/syntax/highlite

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

  test "Buffer with #!/bin/bash shebang":
    var buffer = newTextBuffer("#!/bin/bash\necho hello")
    check buffer.isSh == false

  test "Buffer without shebang":
    var buffer = newTextBuffer("echo hello")
    check buffer.isSh == false

  test "Empty buffer":
    var buffer = newTextBuffer("")
    check buffer.isSh == false

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
    let cmd = clangQuickRunCommand("/path/to/file.c", settings)
    check cmd.cmd == "/bin/bash"
    check cmd.args.len == 2
    check cmd.args[0] == "-c"
    check "gcc" in cmd.args[1]
    check "./.out" in cmd.args[1]

  test "C command with options":
    let settings = QuickRunConfig(clangOptions: some("-Wall -Wextra"))
    let cmd = clangQuickRunCommand("/path/to/file.c", settings)
    check cmd.cmd == "/bin/bash"
    check "-Wall -Wextra" in cmd.args[1]

suite "QuickRunUtils - cppQuickRunCommand":
  test "Basic C++ command":
    let settings = QuickRunConfig(cppOptions: none(string))
    let cmd = cppQuickRunCommand("/path/to/file.cpp", settings)
    check cmd.cmd == "/bin/bash"
    check cmd.args.len == 2
    check cmd.args[0] == "-c"
    check "g++" in cmd.args[1]
    check "./.out" in cmd.args[1]

  test "C++ command with options":
    let settings = QuickRunConfig(cppOptions: some("-std=c++17"))
    let cmd = cppQuickRunCommand("/path/to/file.cpp", settings)
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
    let cmd = rustQuickRunCommand("/path/to/file.rs", settings)
    check cmd.cmd == "/bin/bash"
    check cmd.args.len == 2
    check cmd.args[0] == "-c"
    check "rustc" in cmd.args[1]
    check "./file" in cmd.args[1]

  test "Rust command extracts correct output name":
    let settings = QuickRunConfig()
    let cmd = rustQuickRunCommand("/some/deep/path/myprogram.rs", settings)
    check "./myprogram" in cmd.args[1]
    check "rustc" in cmd.args[1]

  test "Rust command with simple filename":
    let settings = QuickRunConfig()
    let cmd = rustQuickRunCommand("main.rs", settings)
    check "./main" in cmd.args[1]

suite "QuickRunUtils - quickRunCommand":
  test "Nim language":
    var buffer = newTextBuffer("echo \"hello\"")
    buffer.language = SourceLanguage.langNim
    let settings =
      QuickRunConfig(nimAdvancedCommand: none(string), nimOptions: none(string))
    let result =
      quickRunCommand("/path/to/file.nim", SourceLanguage.langNim, buffer, settings)
    check result.isOk
    check result.get.cmd == "nim"

  test "C language":
    var buffer = newTextBuffer("#include <stdio.h>\nint main() { return 0; }")
    buffer.language = SourceLanguage.langC
    let settings = QuickRunConfig(clangOptions: none(string))
    let result =
      quickRunCommand("/path/to/file.c", SourceLanguage.langC, buffer, settings)
    check result.isOk
    check result.get.cmd == "/bin/bash"
    check "gcc" in result.get.args[1]

  test "C++ language":
    var buffer = newTextBuffer("#include <iostream>\nint main() { return 0; }")
    buffer.language = SourceLanguage.langCpp
    let settings = QuickRunConfig(cppOptions: none(string))
    let result =
      quickRunCommand("/path/to/file.cpp", SourceLanguage.langCpp, buffer, settings)
    check result.isOk
    check result.get.cmd == "/bin/bash"
    check "g++" in result.get.args[1]

  test "Rust language":
    var buffer = newTextBuffer("fn main() {}")
    buffer.language = SourceLanguage.langRust
    let settings = QuickRunConfig()
    let result =
      quickRunCommand("/path/to/file.rs", SourceLanguage.langRust, buffer, settings)
    check result.isOk
    check result.get.cmd == "/bin/bash"
    check "rustc" in result.get.args[1]

  test "Python language":
    var buffer = newTextBuffer("print('hello')")
    buffer.language = SourceLanguage.langPython
    let settings = QuickRunConfig()
    let result =
      quickRunCommand("/path/to/script.py", SourceLanguage.langPython, buffer, settings)
    check result.isOk
    check result.get.cmd == "python3"

  test "Shell language with sh shebang":
    var buffer = newTextBuffer("#!/bin/sh\necho hello")
    buffer.language = SourceLanguage.langShell
    let settings = QuickRunConfig(shOptions: none(string), bashOptions: none(string))
    let result =
      quickRunCommand("/path/to/script.sh", SourceLanguage.langShell, buffer, settings)
    check result.isOk
    check result.get.cmd == "/bin/sh"

  test "Shell language with bash shebang":
    var buffer = newTextBuffer("#!/bin/bash\necho hello")
    buffer.language = SourceLanguage.langShell
    let settings = QuickRunConfig(shOptions: none(string), bashOptions: none(string))
    let result =
      quickRunCommand("/path/to/script.sh", SourceLanguage.langShell, buffer, settings)
    check result.isOk
    check result.get.cmd == "/bin/bash"

  test "Unsupported language returns error":
    var buffer = newTextBuffer("<html></html>")
    buffer.language = SourceLanguage.langHtml
    let settings = QuickRunConfig()
    let result =
      quickRunCommand("/path/to/file.html", SourceLanguage.langHtml, buffer, settings)
    check result.isErr
    check "Unsupported language" in result.error

suite "QuickRunUtils - quickRunBufferExists":
  test "Always returns false (TODO implementation)":
    let buffers: seq[TextBuffer] = @[newTextBuffer("test")]
    check quickRunBufferExists(buffers, "/path/to/file") == false

  test "Empty buffer list returns false":
    let buffers: seq[TextBuffer] = @[]
    check quickRunBufferExists(buffers, "/path/to/file") == false

  test "Multiple buffers returns false":
    let buffers =
      @[newTextBuffer("content1"), newTextBuffer("content2"), newTextBuffer("content3")]
    check quickRunBufferExists(buffers, "/any/path") == false

suite "QuickRunUtils - quickRunBufferIndex":
  test "Always returns none (TODO implementation)":
    let buffers: seq[TextBuffer] = @[newTextBuffer("test")]
    check quickRunBufferIndex(buffers, "/path/to/file").isNone

  test "Empty buffer list returns none":
    let buffers: seq[TextBuffer] = @[]
    check quickRunBufferIndex(buffers, "/path/to/file").isNone

  test "Multiple buffers returns none":
    let buffers =
      @[newTextBuffer("content1"), newTextBuffer("content2"), newTextBuffer("content3")]
    check quickRunBufferIndex(buffers, "/any/path").isNone

suite "QuickRunUtils - prepareQuickRun":
  test "Prepare QuickRun for Nim file with path":
    var buffer = newTextBuffer("echo \"hello\"", some("/tmp/test.nim"))
    buffer.language = SourceLanguage.langNim

    # Create temp file
    writeFile("/tmp/test.nim", "echo \"hello\"")
    defer:
      removeFile("/tmp/test.nim")

    let config = newEditorConfig()
    let result = prepareQuickRun(buffer, config)
    check result.isOk
    check result.get.filePath == "/tmp/test.nim"
    check result.get.isTempFile == false
    check result.get.command.cmd == "nim"

  test "Prepare QuickRun for unsaved buffer creates temp file":
    var buffer = newTextBuffer("print('hello')")
    buffer.language = SourceLanguage.langPython

    var config = newEditorConfig()
    config.quickRun.saveBufferWhenQuickRun = true

    let result = prepareQuickRun(buffer, config)
    check result.isOk
    check result.get.isTempFile == true
    check result.get.filePath == "quickruntemp.py"
    check result.get.command.cmd == "python3"

    # Cleanup temp file
    if fileExists("quickruntemp.py"):
      removeFile("quickruntemp.py")

  test "Prepare QuickRun for unsupported language returns error":
    var buffer = newTextBuffer("<html></html>")
    buffer.language = SourceLanguage.langHtml

    let config = newEditorConfig()
    let result = prepareQuickRun(buffer, config)
    check result.isErr
    check "Unknown language" in result.error or "Unsupported language" in result.error

  test "Prepare QuickRun with saveBufferWhenQuickRun disabled":
    var buffer = newTextBuffer("echo \"hello\"", some("/tmp/test_nosave.nim"))
    buffer.language = SourceLanguage.langNim

    # Create file first
    writeFile("/tmp/test_nosave.nim", "echo \"original\"")
    defer:
      removeFile("/tmp/test_nosave.nim")

    var config = newEditorConfig()
    config.quickRun.saveBufferWhenQuickRun = false

    let result = prepareQuickRun(buffer, config)
    check result.isOk
    check result.get.filePath == "/tmp/test_nosave.nim"
    check result.get.isTempFile == false

  test "Prepare QuickRun with nonexistent file path uses temp file":
    var buffer = newTextBuffer("echo \"hello\"", some("/nonexistent/path/file.nim"))
    buffer.language = SourceLanguage.langNim

    let config = newEditorConfig()
    let result = prepareQuickRun(buffer, config)
    check result.isOk
    check result.get.isTempFile == true
    check result.get.filePath == "quickruntemp.nim"

    # Cleanup temp file
    if fileExists("quickruntemp.nim"):
      removeFile("quickruntemp.nim")

  test "Prepare QuickRun for unsupported language with no filePath":
    var buffer = newTextBuffer("unsupported content")
    buffer.language = SourceLanguage.langMarkdown

    let config = newEditorConfig()
    let result = prepareQuickRun(buffer, config)
    check result.isErr
    check "Unknown language" in result.error

  test "Prepare QuickRun for each supported language temp file":
    # Test Nim
    block:
      var buffer = newTextBuffer("echo 1")
      buffer.language = SourceLanguage.langNim
      let config = newEditorConfig()
      let result = prepareQuickRun(buffer, config)
      check result.isOk
      check result.get.filePath == "quickruntemp.nim"
      if fileExists("quickruntemp.nim"):
        removeFile("quickruntemp.nim")

    # Test C
    block:
      var buffer = newTextBuffer("int main() { return 0; }")
      buffer.language = SourceLanguage.langC
      let config = newEditorConfig()
      let result = prepareQuickRun(buffer, config)
      check result.isOk
      check result.get.filePath == "quickruntemp.c"
      if fileExists("quickruntemp.c"):
        removeFile("quickruntemp.c")

    # Test C++
    block:
      var buffer = newTextBuffer("int main() { return 0; }")
      buffer.language = SourceLanguage.langCpp
      let config = newEditorConfig()
      let result = prepareQuickRun(buffer, config)
      check result.isOk
      check result.get.filePath == "quickruntemp.cpp"
      if fileExists("quickruntemp.cpp"):
        removeFile("quickruntemp.cpp")

    # Test Shell
    block:
      var buffer = newTextBuffer("echo hello")
      buffer.language = SourceLanguage.langShell
      let config = newEditorConfig()
      let result = prepareQuickRun(buffer, config)
      check result.isOk
      check result.get.filePath == "quickruntemp.bash"
      if fileExists("quickruntemp.bash"):
        removeFile("quickruntemp.bash")

    # Test Rust
    block:
      var buffer = newTextBuffer("fn main() {}")
      buffer.language = SourceLanguage.langRust
      let config = newEditorConfig()
      let result = prepareQuickRun(buffer, config)
      check result.isOk
      check result.get.filePath == "quickruntemp.rs"
      if fileExists("quickruntemp.rs"):
        removeFile("quickruntemp.rs")

suite "QuickRunUtils - QuickRunProcess isRunning and isFinish":
  test "isRunning and isFinish for running process":
    proc runTest(): Future[tuple[running: bool, finish: bool]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "sleep", args: @["1"], workingDir: getCurrentDir()
      )

      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let qp = QuickRunProcess(
          command: cmd, filePath: "test.nim", isTempFile: false, process: r.get
        )
        let running = qp.isRunning
        let finish = qp.isFinish
        qp.process.kill()
        await qp.process.closeAsync()
        return (running, finish)
      else:
        return (false, true)

    let r = waitFor runTest()
    check r.running == true
    check r.finish == false

  test "isRunning and isFinish for completed process":
    proc runTest(): Future[tuple[running: bool, finish: bool]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "echo", args: @["done"], workingDir: getCurrentDir()
      )

      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let qp = QuickRunProcess(
          command: cmd, filePath: "test.nim", isTempFile: false, process: r.get
        )
        discard await qp.process.waitForAsync()
        let running = qp.isRunning
        let finish = qp.isFinish
        return (running, finish)
      else:
        return (true, false)

    let r = waitFor runTest()
    check r.running == false
    check r.finish == true

suite "QuickRunUtils - startBackgroundQuickRun":
  test "Start QuickRun with echo command":
    proc runTest(): Future[tuple[isOk: bool, output: seq[string]]] {.async.} =
      let prepared = QuickRunPrepareResult(
        command: BackgroundProcessCommand(
          cmd: "echo", args: @["quick", "run"], workingDir: getCurrentDir()
        ),
        filePath: "test.nim",
        isTempFile: false,
      )

      let r = await startBackgroundQuickRun(prepared)
      if r.isOk:
        let qp = r.get
        let output = await qp.waitForResultAsync()
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
        isTempFile: false,
      )

      let r = await startBackgroundQuickRun(prepared)
      return r.isErr

    check waitFor(runTest())

suite "QuickRunUtils - waitForResultAsync":
  test "Wait for process and get output":
    proc runTest(): Future[tuple[isOk: bool, output: seq[string]]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "echo", args: @["hello", "world"], workingDir: getCurrentDir()
      )

      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let qp = QuickRunProcess(
          command: cmd, filePath: "test.nim", isTempFile: false, process: r.get
        )
        let output = await qp.waitForResultAsync()
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

      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let qp = QuickRunProcess(
          command: cmd, filePath: "test.sh", isTempFile: false, process: r.get
        )
        let output = await qp.waitForResultAsync()
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

suite "QuickRunUtils - cleanupTempFiles":
  test "Cleanup temp files when isTempFile is true":
    # Create temp files
    const tempPath = "quickruntemp_test.py"
    writeFile(tempPath, "print('test')")

    proc runTest(): Future[void] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "echo", args: @["test"], workingDir: getCurrentDir()
      )
      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let qp = QuickRunProcess(
          command: cmd, filePath: tempPath, isTempFile: true, process: r.get
        )
        discard await qp.waitForResultAsync()

    waitFor runTest()

    # File should be cleaned up
    check not fileExists(tempPath)

  test "No cleanup when isTempFile is false":
    const tempPath = "/tmp/quickrun_test_no_cleanup.nim"
    writeFile(tempPath, "echo \"test\"")
    defer:
      if fileExists(tempPath):
        removeFile(tempPath)

    proc runTest(): Future[void] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "echo", args: @["test"], workingDir: getCurrentDir()
      )
      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let qp = QuickRunProcess(
          command: cmd, filePath: tempPath, isTempFile: false, process: r.get
        )
        discard await qp.waitForResultAsync()

    waitFor runTest()

    # File should still exist
    check fileExists(tempPath)

  test "Cleanup executable file (baseName)":
    # Create temp source and executable files
    const tempPath = "quickruntemp_exec.nim"
    const execPath = "quickruntemp_exec"
    writeFile(tempPath, "echo 1")
    writeFile(execPath, "fake executable")
    defer:
      if fileExists(tempPath):
        removeFile(tempPath)
      if fileExists(execPath):
        removeFile(execPath)

    proc runTest(): Future[void] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "echo", args: @["test"], workingDir: getCurrentDir()
      )
      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let qp = QuickRunProcess(
          command: cmd, filePath: tempPath, isTempFile: true, process: r.get
        )
        discard await qp.waitForResultAsync()

    waitFor runTest()

    # Both files should be cleaned up
    check not fileExists(tempPath)
    check not fileExists(execPath)

  test "Cleanup .out file for C/C++":
    # Create temp source and .out files
    const tempPath = "quickruntemp_c.c"
    const outPath = ".out"
    writeFile(tempPath, "int main() { return 0; }")
    writeFile(outPath, "fake executable")
    defer:
      if fileExists(tempPath):
        removeFile(tempPath)
      if fileExists(outPath):
        removeFile(outPath)

    proc runTest(): Future[void] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "echo", args: @["test"], workingDir: getCurrentDir()
      )
      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let qp = QuickRunProcess(
          command: cmd, filePath: tempPath, isTempFile: true, process: r.get
        )
        discard await qp.waitForResultAsync()

    waitFor runTest()

    # All files should be cleaned up
    check not fileExists(tempPath)
    check not fileExists(outPath)

suite "QuickRunUtils - cancel and kill":
  test "Cancel running process":
    proc runTest(): Future[bool] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "sleep", args: @["10"], workingDir: getCurrentDir()
      )

      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let qp = QuickRunProcess(
          command: cmd, filePath: "test.sh", isTempFile: false, process: r.get
        )
        qp.cancel()
        await sleepAsync(100.milliseconds)
        let finished = qp.isFinish
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

      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let qp = QuickRunProcess(
          command: cmd, filePath: "test.sh", isTempFile: false, process: r.get
        )
        qp.kill()
        await sleepAsync(100.milliseconds)
        let finished = qp.isFinish
        return finished
      else:
        return false

    let finished = waitFor runTest()
    check finished
