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

## DebouncedLspPoll invariants pinned as regressions across Phase D of the
## LspRequestContext migration (docs §10.5). After Phase D the type carries only
## the debounce timer + exponential-backoff streak; per-request stale-guard
## fields moved to `LspCacheState.pending`.

import std/[unittest, monotimes, times]

import ../src/moepkg/types

suite "DebouncedLspPoll - initDebouncedLspPoll":
  test "Stores the supplied interval and stamps lastUpdate to now":
    let before = getMonoTime()
    let poll = initDebouncedLspPoll(250)
    let after = getMonoTime()

    check poll.interval == 250
    # lastUpdate is stamped inside initDebouncedLspPoll — it must sit within
    # the [before, after] window that brackets the call.
    check poll.lastUpdate >= before
    check poll.lastUpdate <= after

  test "Fresh poll starts with a zero reject streak":
    let poll = initDebouncedLspPoll(500)
    check poll.rejectStreak == 0

suite "DebouncedLspPoll - debounceThreshold":
  test "Streak 0 returns the base interval":
    let poll = DebouncedLspPoll(interval: 500)
    check poll.debounceThreshold() == initDuration(milliseconds = 500)

  test "Streak 1 doubles the base interval":
    let poll = DebouncedLspPoll(interval: 500, rejectStreak: 1)
    check poll.debounceThreshold() == initDuration(milliseconds = 1_000)

  test "Streak 6 (cap) is 64x the base interval":
    let poll = DebouncedLspPoll(interval: 500, rejectStreak: MaxLspDebounceBackoffShift)
    let expectedMs = 500'i64 shl MaxLspDebounceBackoffShift
    check poll.debounceThreshold() == initDuration(milliseconds = expectedMs)

  test "Streak beyond cap saturates at the same threshold":
    let atCap =
      DebouncedLspPoll(interval: 500, rejectStreak: MaxLspDebounceBackoffShift)
    let past =
      DebouncedLspPoll(interval: 500, rejectStreak: MaxLspDebounceBackoffShift + 5)
    check past.debounceThreshold() == atCap.debounceThreshold()

  test "Threshold doubles monotonically from 0 up to the cap":
    # A regression on the exponent — e.g. an accidental `shl (streak - 1)` —
    # would silently change the backoff curve. Pin the doubling directly.
    var prev = initDuration(milliseconds = 0)
    for streak in 0 .. MaxLspDebounceBackoffShift:
      let poll = DebouncedLspPoll(interval: 100, rejectStreak: streak)
      let cur = poll.debounceThreshold()
      if streak == 0:
        check cur == initDuration(milliseconds = 100)
      else:
        check cur == prev * 2
      prev = cur

  test "Different intervals scale independently":
    let a = DebouncedLspPoll(interval: 100, rejectStreak: 3)
    let b = DebouncedLspPoll(interval: 250, rejectStreak: 3)
    check a.debounceThreshold() == initDuration(milliseconds = 800)
    check b.debounceThreshold() == initDuration(milliseconds = 2_000)
