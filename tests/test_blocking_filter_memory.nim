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

# Alone in its file: memory an earlier test freed would absorb the growth.

when defined(linux):
  import std/[unittest, os, strutils]

  import pkg/chronos

  import ../src/moepkg/[background_process, blocking_filter]

  proc statusKb(field: string): int =
    for line in lines("/proc/self/status"):
      if line.startsWith(field & ":"):
        return line.splitWhitespace()[1].parseInt

  proc run(): bool =
    runFilterBlocking(
      BackgroundProcessCommand(cmd: "true", args: @[], workingDir: getTempDir()),
      "",
      InfiniteDuration,
      1024,
    ).isOk

  suite "runFilterBlocking - memory":
    test "Runs do not add up in memory":
      # A thread's dispatcher and the cycles it leaves outlive the thread
      # unless it lets go of them: tens of KB a run.
      var failed = 0
      for _ in 0 ..< 50:
        if not run():
          inc failed
      let before = statusKb("VmRSS")
      for _ in 0 ..< 300:
        if not run():
          inc failed
      check failed == 0
      check statusKb("VmRSS") - before < 4096

    test "The input is not copied on its way to the command":
      const size = 64 * 1024 * 1024
      var input = 'x'.repeat(size)
      let before = statusKb("VmHWM")
      let r = runFilterBlocking(
        BackgroundProcessCommand(
          cmd: "sh", args: @["-c", "cat > /dev/null"], workingDir: getTempDir()
        ),
        move input,
        InfiniteDuration,
        1024,
      )
      check r.isOk
      check statusKb("VmHWM") - before < size div 1024 div 2
