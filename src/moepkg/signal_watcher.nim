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

## Answering the deadly signals, so unsaved buffers are preserved when moe is
## killed. Linux only (`sigtimedwait` and `si_code`); elsewhere a signal ends
## moe at once, while a crash still preserves.

const signalWatcherSupported* = defined(linux) and not defined(moe.embedded)
  ## The embedded core leaves signals and the terminal to its host.

when signalWatcherSupported:
  import signal_watcher_linux
  export signal_watcher_linux
else:
  import pkg/chronos

  proc startSignalWatcher*(answer = 10.seconds, finish = 20.seconds): bool =
    false

  proc signalWatcherRunning*(): bool =
    false

  proc loopAnswers*() =
    discard

  proc signalForwarded*(): Future[void] {.async: (raises: [CancelledError]).} =
    await sleepAsync(InfiniteDuration)

  proc takenSignal*(): cint =
    0

  proc waitForTakenSignal*(timeout: Duration): cint =
    0

  proc beginPreserving*(): bool =
    true

  proc beginWindingDown*() =
    discard

  proc settle*() =
    discard

  template withTerminalHandedOver*(body: untyped) =
    body

  template withCommandInTerminal*(target: int, body: untyped) =
    body
