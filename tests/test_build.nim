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

import std/[unittest, os, strutils]

import pkg/chronos

import ../src/moepkg/build {.all.}
import ../src/moepkg/syntax/tokenizer

suite "Build - parseCommandString":
  test "Parse simple command":
    let cmd = parseCommandString("echo")
    check cmd.cmd == "echo"
    check cmd.args.len == 0

  test "Parse command with single arg":
    let cmd = parseCommandString("nim c")
    check cmd.cmd == "nim"
    check cmd.args == @["c"]

  test "Parse command with multiple args":
    let cmd = parseCommandString("nim c -d:release file.nim")
    check cmd.cmd == "nim"
    check cmd.args == @["c", "-d:release", "file.nim"]

  test "Parse empty string":
    let cmd = parseCommandString("")
    check cmd.cmd == ""
    check cmd.args.len == 0

  test "Parse cargo build command":
    let cmd = parseCommandString("cargo build --release")
    check cmd.cmd == "cargo"
    check cmd.args == @["build", "--release"]

  test "Collapse consecutive whitespace":
    let cmd = parseCommandString("nim   c\t\tfile.nim")
    check cmd.cmd == "nim"
    check cmd.args == @["c", "file.nim"]

  test "Trim leading and trailing whitespace":
    let cmd = parseCommandString("  nim c file.nim  ")
    check cmd.cmd == "nim"
    check cmd.args == @["c", "file.nim"]

  test "Double-quoted arg preserves inner spaces":
    let cmd = parseCommandString("nim c \"-d:foo bar\" file.nim")
    check cmd.cmd == "nim"
    check cmd.args == @["c", "-d:foo bar", "file.nim"]

  test "Single-quoted arg is fully literal":
    let cmd = parseCommandString("echo 'a \"b\" \\c'")
    check cmd.cmd == "echo"
    check cmd.args == @["a \"b\" \\c"]

  test "Backslash escapes space outside quotes":
    let cmd = parseCommandString("cmd a\\ b c")
    check cmd.cmd == "cmd"
    check cmd.args == @["a b", "c"]

  test "Backslash escapes quote inside double quotes":
    let cmd = parseCommandString("echo \"say \\\"hi\\\"\"")
    check cmd.cmd == "echo"
    check cmd.args == @["say \"hi\""]

  test "Empty quoted string is a token":
    let cmd = parseCommandString("cmd \"\" x")
    check cmd.cmd == "cmd"
    check cmd.args == @["", "x"]

  test "Whitespace-only string yields empty command":
    let cmd = parseCommandString("   \t  ")
    check cmd.cmd == ""
    check cmd.args.len == 0

suite "Build - nimBuildCommand":
  test "Generate nim build command":
    let cmd = nimBuildCommand("/path/to/file.nim")
    check cmd.cmd == "nim"
    check cmd.args == @["c", "/path/to/file.nim"]

  test "Generate nim build command with relative path":
    let cmd = nimBuildCommand("src/main.nim")
    check cmd.cmd == "nim"
    check cmd.args == @["c", "src/main.nim"]

suite "Build - rustBuildCommand":
  test "Generate rust build command":
    let cmd = rustBuildCommand("/path/to/file.rs")
    check cmd.cmd == "cargo"
    check cmd.args == @["build"]

  test "Generate rust build command ignores path":
    let cmd1 = rustBuildCommand("file1.rs")
    let cmd2 = rustBuildCommand("file2.rs")
    check cmd1.cmd == cmd2.cmd
    check cmd1.args == cmd2.args

suite "Build - buildCommand":
  test "Build command for Nim":
    let r = buildCommand("/path/to/file.nim", SourceLanguage.langNim, "/workspace")
    check r.isOk
    let cmd = r.get
    check cmd.cmd == "nim"
    check cmd.args == @["c", "/path/to/file.nim"]
    check cmd.workingDir == "/workspace"

  test "Build command for Rust":
    let r = buildCommand("/path/to/file.rs", SourceLanguage.langRust, "/workspace")
    check r.isOk
    let cmd = r.get
    check cmd.cmd == "cargo"
    check cmd.args == @["build"]
    check cmd.workingDir == "/workspace"

  test "Build command for unsupported language":
    let r = buildCommand("/path/to/file.py", SourceLanguage.langPython, "/workspace")
    check r.isErr
    check r.error == "Unknown language"

  test "Build command for langNone":
    let r = buildCommand("/path/to/file.txt", SourceLanguage.langNone, "/workspace")
    check r.isErr

suite "Build - BuildProcess isRunning and isFinish":
  test "isRunning and isFinish for running process":
    proc runTest(): Future[tuple[running: bool, finish: bool]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "sleep", args: @["1"], workingDir: getCurrentDir()
      )

      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let bp = BuildProcess(command: cmd, filePath: "test.nim", process: r.get)
        let running = bp.isRunning
        let finish = bp.isFinish
        bp.process.kill()
        await bp.process.closeAsync()
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
        let bp = BuildProcess(command: cmd, filePath: "test.nim", process: r.get)
        discard await bp.process.waitForAsync(30.seconds)
        let running = bp.isRunning
        let finish = bp.isFinish
        return (running, finish)
      else:
        return (true, false)

    let r = waitFor runTest()
    check r.running == false
    check r.finish == true

suite "Build - startBackgroundBuild with path":
  test "Start build with unsupported language returns error":
    proc runTest(): Future[bool] {.async.} =
      let r = await startBackgroundBuild(
        "/path/to/file.py", SourceLanguage.langPython, getCurrentDir()
      )
      return r.isErr

    check waitFor(runTest())

  test "Start build with langNone returns error":
    proc runTest(): Future[bool] {.async.} =
      let r = await startBackgroundBuild(
        "/path/to/file.txt", SourceLanguage.langNone, getCurrentDir()
      )
      return r.isErr

    check waitFor(runTest())

suite "Build - startBackgroundBuild with custom command":
  test "Start build with custom echo command":
    proc runTest(): Future[tuple[isOk: bool, output: seq[string]]] {.async.} =
      let customCmd: BuildCommand = (cmd: "echo", args: @["build", "success"])
      let r =
        await startBackgroundBuild(customCmd, SourceLanguage.langNim, getCurrentDir())
      if r.isOk:
        let bp = r.get
        let output = (await bp.waitForAsync(30.seconds)).get
        return (true, output)
      else:
        return (false, @[])

    let r = waitFor runTest()
    check r.isOk
    check r.output.len >= 1
    check r.output[0] == "build success"

  test "Start build with empty command returns error":
    proc runTest(): Future[bool] {.async.} =
      let customCmd: BuildCommand = (cmd: "", args: @[])
      let r =
        await startBackgroundBuild(customCmd, SourceLanguage.langNim, getCurrentDir())
      return r.isErr

    check waitFor(runTest())

  test "Start build with working directory":
    proc runTest(): Future[tuple[isOk: bool, output: seq[string]]] {.async.} =
      let customCmd: BuildCommand = (cmd: "pwd", args: @[])
      let r = await startBackgroundBuild(customCmd, SourceLanguage.langNim, "/tmp")
      if r.isOk:
        let bp = r.get
        let output = (await bp.waitForAsync(30.seconds)).get
        return (true, output)
      else:
        return (false, @[])

    let r = waitFor runTest()
    check r.isOk
    check r.output.len >= 1
    check r.output[0] == "/tmp"

  test "BuildProcess stores command and filePath":
    proc runTest(): Future[tuple[cmd: string, args: seq[string]]] {.async.} =
      let customCmd: BuildCommand = (cmd: "echo", args: @["test"])
      let r =
        await startBackgroundBuild(customCmd, SourceLanguage.langNim, getCurrentDir())
      if r.isOk:
        let bp = r.get
        discard await bp.waitForAsync(30.seconds)
        return (bp.command.cmd, bp.command.args)
      else:
        return ("", @[])

    let r = waitFor runTest()
    check r.cmd == "echo"
    check r.args == @["test"]

suite "Build - startBackgroundBuildOnSave":
  test "Start build on save with custom command":
    proc runTest(): Future[tuple[isOk: bool, output: seq[string]]] {.async.} =
      let r = await startBackgroundBuildOnSave(
        "/path/to/file.nim",
        SourceLanguage.langNim,
        customCommand = "echo custom build",
        workspaceRoot = getCurrentDir(),
      )
      if r.isOk:
        let bp = r.get
        let output = (await bp.waitForAsync(30.seconds)).get
        return (true, output)
      else:
        return (false, @[])

    let r = waitFor runTest()
    check r.isOk
    check r.output.len >= 1
    check r.output[0] == "custom build"

  test "Start build on save without custom command for unsupported language":
    proc runTest(): Future[bool] {.async.} =
      let r = await startBackgroundBuildOnSave(
        "/path/to/file.py",
        SourceLanguage.langPython,
        customCommand = "",
        workspaceRoot = getCurrentDir(),
      )
      return r.isErr

    check waitFor(runTest())

  test "Start build on save with empty custom command uses default":
    proc runTest(): Future[bool] {.async.} =
      # For unsupported language without custom command, should fail
      let r = await startBackgroundBuildOnSave(
        "/path/to/file.txt",
        SourceLanguage.langNone,
        customCommand = "",
        workspaceRoot = getCurrentDir(),
      )
      return r.isErr

    check waitFor(runTest())

suite "Build - waitForAsync":
  test "Wait for build process and get output":
    proc runTest(): Future[tuple[output: seq[string], processIsNil: bool]] {.async.} =
      let customCmd: BuildCommand = (cmd: "echo", args: @["build output"])
      let r =
        await startBackgroundBuild(customCmd, SourceLanguage.langNim, getCurrentDir())
      if r.isOk:
        let bp = r.get
        let output = (await bp.waitForAsync(30.seconds)).get
        return (output, bp.process.process.isNil)
      else:
        return (@[], false)

    let r = waitFor runTest()
    check r.output.len >= 1
    check r.output[0] == "build output"
    check r.processIsNil

  test "Wait for multi-line output":
    proc runTest(): Future[seq[string]] {.async.} =
      let customCmd: BuildCommand =
        (cmd: "sh", args: @["-c", "echo line1; echo line2; echo line3"])
      let r =
        await startBackgroundBuild(customCmd, SourceLanguage.langNim, getCurrentDir())
      if r.isOk:
        let bp = r.get
        return (await bp.waitForAsync(30.seconds)).get
      else:
        return @[]

    let output = waitFor runTest()
    check output.len >= 3
    check output[0] == "line1"
    check output[1] == "line2"
    check output[2] == "line3"

suite "Build - error handling":
  test "Invalid executable returns error":
    proc runTest(): Future[bool] {.async.} =
      let customCmd: BuildCommand =
        (cmd: "/nonexistent/command/that/does/not/exist", args: @[])
      let r =
        await startBackgroundBuild(customCmd, SourceLanguage.langNim, getCurrentDir())
      return r.isErr

    check waitFor(runTest())

  test "Error message contains 'Failed to exec build commands'":
    proc runTest(): Future[string] {.async.} =
      let r = await startBackgroundBuild(
        "/path/to/file.py", SourceLanguage.langPython, getCurrentDir()
      )
      if r.isErr:
        return r.error
      else:
        return ""

    let errMsg = waitFor runTest()
    check "Failed to exec build commands" in errMsg
