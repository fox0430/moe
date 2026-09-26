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

import pkg/[chronos, results]

import ../src/moepkg/build {.all.}
import ../src/moepkg/child_process
import ../src/moepkg/command_string
import ../src/moepkg/syntax/tokenizer

suite "Build - parseCommandString":
  test "Parse simple command":
    let cmd = parseCommandString("echo").get
    check cmd.cmd == "echo"
    check cmd.args.len == 0

  test "Parse command with single arg":
    let cmd = parseCommandString("nim c").get
    check cmd.cmd == "nim"
    check cmd.args == @["c"]

  test "Parse command with multiple args":
    let cmd = parseCommandString("nim c -d:release file.nim").get
    check cmd.cmd == "nim"
    check cmd.args == @["c", "-d:release", "file.nim"]

  test "Parse empty string":
    let cmd = parseCommandString("").get
    check cmd.cmd == ""
    check cmd.args.len == 0

  test "Parse cargo build command":
    let cmd = parseCommandString("cargo build --release").get
    check cmd.cmd == "cargo"
    check cmd.args == @["build", "--release"]

  test "Collapse consecutive whitespace":
    let cmd = parseCommandString("nim   c\t\tfile.nim").get
    check cmd.cmd == "nim"
    check cmd.args == @["c", "file.nim"]

  test "Trim leading and trailing whitespace":
    let cmd = parseCommandString("  nim c file.nim  ").get
    check cmd.cmd == "nim"
    check cmd.args == @["c", "file.nim"]

  test "Double-quoted arg preserves inner spaces":
    let cmd = parseCommandString("nim c \"-d:foo bar\" file.nim").get
    check cmd.cmd == "nim"
    check cmd.args == @["c", "-d:foo bar", "file.nim"]

  test "Single-quoted arg is fully literal":
    let cmd = parseCommandString("echo 'a \"b\" \\c'").get
    check cmd.cmd == "echo"
    check cmd.args == @["a \"b\" \\c"]

  test "Backslash escapes space outside quotes":
    let cmd = parseCommandString("cmd a\\ b c").get
    check cmd.cmd == "cmd"
    check cmd.args == @["a b", "c"]

  test "Backslash escapes quote inside double quotes":
    let cmd = parseCommandString("echo \"say \\\"hi\\\"\"").get
    check cmd.cmd == "echo"
    check cmd.args == @["say \"hi\""]

  test "Empty quoted string is a token":
    let cmd = parseCommandString("cmd \"\" x").get
    check cmd.cmd == "cmd"
    check cmd.args == @["", "x"]

  test "Whitespace-only string yields empty command":
    let cmd = parseCommandString("   \t  ").get
    check cmd.cmd == ""
    check cmd.args.len == 0

  test "Unterminated double quote is an error":
    let r = parseCommandString("cargo build --features \"a b")
    check r.isErr
    check r.error == "unterminated quote"

  test "Unterminated single quote is an error":
    let r = parseCommandString("echo 'abc")
    check r.isErr
    check r.error == "unterminated quote"

  test "Unterminated quote after valid tokens is an error":
    let r = parseCommandString("nim c \"-d:foo bar")
    check r.isErr

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

proc startBuild(
    cmd: string, args: seq[string] = @[], dir = getCurrentDir(), path = ""
): Result[BuildProcess, string] =
  startBackgroundBuild(
    BackgroundProcessCommand(cmd: cmd, args: args, workingDir: dir), path
  )

suite "Build - buildOnSaveCommand":
  test "A custom command runs as given, in the workspace root":
    let r = buildOnSaveCommand(
      "/path/to/file.nim",
      SourceLanguage.langNim,
      customCommand = "echo custom build",
      workspaceRoot = "/workspace",
    )
    check r.isOk
    check r.get.cmd == "echo"
    check r.get.args == @["custom", "build"]
    check r.get.workingDir == "/workspace"

  test "Without one, the language's own command":
    let r = buildOnSaveCommand(
      "/path/to/file.nim", SourceLanguage.langNim, workspaceRoot = "/workspace"
    )
    check r.isOk
    check r.get.cmd == "nim"
    check r.get.args == @["c", "/path/to/file.nim"]

  test "A custom command of only blanks is refused":
    check buildOnSaveCommand("/path/to/file.nim", SourceLanguage.langNim, "   ").isErr

  test "A custom command with an unterminated quote is refused":
    let r = buildOnSaveCommand(
      "/path/to/file.nim",
      SourceLanguage.langNim,
      customCommand = "cargo build --features \"a b",
      workspaceRoot = "/workspace",
    )
    check r.isErr
    check r.error == "unterminated quote"

  test "A language without a build command is refused":
    let r = buildOnSaveCommand("/path/to/file.py", SourceLanguage.langPython)
    check r.isErr
    check "Failed to exec build commands" in r.error
    check buildOnSaveCommand("/path/to/file.txt", SourceLanguage.langNone).isErr

suite "Build - startBackgroundBuild":
  test "Start a build and read its output":
    proc runTest(): Future[seq[string]] {.async.} =
      let r = startBuild("echo", @["build", "success"])
      if r.isErr:
        return @[]
      return (await r.get.waitForAsync(30.seconds)).get

    let output = waitFor runTest()
    check output.len >= 1
    check output[0] == "build success"

  test "The build runs in its working directory":
    proc runTest(): Future[seq[string]] {.async.} =
      let r = startBuild("pwd")
      if r.isErr:
        return @[]
      return (await r.get.waitForAsync(30.seconds)).get

    let output = waitFor runTest()
    check output.len >= 1
    check output[0] == getCurrentDir()

  test "BuildProcess stores command and filePath":
    let r = startBuild("echo", @["test"], path = "/src/a.nim")
    check r.isOk
    check r.get.command.cmd == "echo"
    check r.get.command.args == @["test"]
    check r.get.filePath == "/src/a.nim"
    discard waitFor r.get.waitForAsync(30.seconds)

suite "Build - waitForAsync":
  test "Wait for build process and get output":
    proc runTest(): Future[tuple[output: seq[string], released: bool]] {.async.} =
      let r = startBuild("echo", @["build output"])
      if r.isErr:
        return (@[], false)
      let output = (await r.get.waitForAsync(30.seconds)).get
      return (output, r.get.process.process.released)

    let r = waitFor runTest()
    check r.output.len >= 1
    check r.output[0] == "build output"
    check r.released

  test "Wait for multi-line output":
    proc runTest(): Future[seq[string]] {.async.} =
      let r = startBuild("sh", @["-c", "echo line1; echo line2; echo line3"])
      if r.isErr:
        return @[]
      return (await r.get.waitForAsync(30.seconds)).get

    let output = waitFor runTest()
    check output.len >= 3
    check output[0] == "line1"
    check output[1] == "line2"
    check output[2] == "line3"

suite "Build - error handling":
  test "Invalid executable returns error":
    let r = startBuild("/nonexistent/command/that/does/not/exist")
    check r.isErr
    check "Failed to exec build commands" in r.error
