#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import std/unittest
import std/strutils
import std/os
import pkg/results
import moepkg/terminal
import moepkg/unicodeext
import moepkg/gapbuffer

when not defined(windows):
  suite "Terminal functionality":
    test "Create terminal buffer":
      let result = newTerminalBuffer("/bin/echo", "/tmp", 24, 80)
      check result.isOk

      if result.isOk:
        var terminalBuffer = result.get
        check terminalBuffer.command == "/bin/echo"
        check terminalBuffer.workingDir == "/tmp"
        check terminalBuffer.state == TerminalState.running
        check terminalBuffer.buffer.len() >= 1
        terminalBuffer.closeTerminal()

    test "Strip ANSI escape codes":
      # Test basic ANSI escape sequences
      block:
        let input = "\x1b[31mHello\x1b[0m World"
        let cleaned = stripAnsiEscapeCodes(input)
        check cleaned == "Hello World"

      # Test CSI sequences
      block:
        let input = "\x1b[2JClear\x1b[H"
        let cleaned = stripAnsiEscapeCodes(input)
        check cleaned == "Clear"

      # Test OSC sequences
      block:
        let input = "\x1b]0;Window Title\x07Content"
        let cleaned = stripAnsiEscapeCodes(input)
        check cleaned == "Content"

      # Test mixed content
      block:
        let input = "Normal \x1b[32mgreen\x1b[0m text"
        let cleaned = stripAnsiEscapeCodes(input)
        check cleaned == "Normal green text"

    test "Process terminal output":
      var terminalBuffer = newTerminalBuffer("/bin/sh", "/tmp").get

      # Test basic output processing
      block:
        let testData = "Hello World\n"
        terminalBuffer.processTerminalOutput(testData)
        check terminalBuffer.buffer.len() >= 2 # Should have output line + input line
        let firstLine = $terminalBuffer.buffer[0]
        check firstLine == "Hello World"

      # Test ANSI escape sequence filtering
      block:
        let testData = "\x1b[32mGreen Text\x1b[0m\n"
        terminalBuffer.processTerminalOutput(testData)
        let lastOutputLine = $terminalBuffer.buffer[terminalBuffer.buffer.len() - 2]
          # Last line before input line
        check lastOutputLine == "Green Text"

      # Test carriage return handling (should overwrite current line)
      block:
        let testData = "First\rSecond\n"
        let initialLen = terminalBuffer.buffer.len()
        terminalBuffer.processTerminalOutput(testData)
        # Should have only "Second", not "First"
        let lastOutputLine = $terminalBuffer.buffer[terminalBuffer.buffer.len() - 2]
        check lastOutputLine == "Second"

      # Test multiple carriage returns (like Fish shell prompt)
      block:
        let testData = "prompt\r\x1b[42Cprompt again\r\x1b[42Cfinal prompt\n"
        terminalBuffer.processTerminalOutput(testData)
        let lastOutputLine = $terminalBuffer.buffer[terminalBuffer.buffer.len() - 2]
        check lastOutputLine == "final prompt"

      # Test empty line handling
      block:
        let initialLen = terminalBuffer.buffer.len()
        terminalBuffer.processTerminalOutput("\n")
        # Should not add empty lines
        check terminalBuffer.buffer.len() == initialLen

      terminalBuffer.closeTerminal()

    test "Write to terminal":
      var terminalBuffer = newTerminalBuffer("/bin/cat", "/tmp").get
      let forkResult = terminalBuffer.forkAndExec()
      check forkResult.isOk

      # Test writing to terminal
      let writeResult = terminalBuffer.writeToTerminal("test input\n")
      check writeResult.isOk

      terminalBuffer.closeTerminal()

    test "Terminal with simple command":
      var terminalBuffer = newTerminalBuffer("/bin/echo", "/tmp").get
      let forkResult = terminalBuffer.forkAndExec()
      check forkResult.isOk

      # Write a simple command
      let writeResult = terminalBuffer.writeToTerminal("Hello Terminal\n")
      check writeResult.isOk

      # Wait a bit for the command to execute
      sleep(100)

      # Update buffer to get output
      terminalBuffer.updateTerminalBuffer()

      # Check if we got some output
      check terminalBuffer.buffer.len() > 0

      terminalBuffer.closeTerminal()
else:
  suite "Terminal functionality (Windows not supported)":
    test "Skip on Windows":
      skip()
