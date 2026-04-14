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

## Fuzzy matching and scoring utilities
##
## Shared by both insert mode completion and command mode completion.

import std/strutils

proc fuzzyMatch*(pattern, text: string): bool =
  ## Simple fuzzy match - check if pattern chars appear in order in text
  if pattern.len == 0:
    return true
  if text.len == 0:
    return false

  let lowerPattern = pattern.toLowerAscii
  let lowerText = text.toLowerAscii

  var patternIdx = 0
  for c in lowerText:
    if patternIdx < lowerPattern.len and c == lowerPattern[patternIdx]:
      inc patternIdx
  return patternIdx >= lowerPattern.len

proc matchScore*(pattern, text: string): int =
  ## Calculate match score (higher = better)
  ## Prefers: exact prefix match > fuzzy match > length similarity
  if pattern.len == 0:
    return 0

  let lowerPattern = pattern.toLowerAscii
  let lowerText = text.toLowerAscii

  # Exact prefix match gets highest score
  if lowerText.startsWith(lowerPattern):
    result = 1000 + (100 - min(text.len, 100)) # Prefer shorter words
    # Bonus for case-sensitive match
    if text.startsWith(pattern):
      result += 50
  else:
    # Fuzzy match score using forward + reverse pass for optimal consecutive
    # bonus. Forward greedy finds the earliest match positions; reverse greedy
    # from the last forward-matched position finds positions that maximize
    # consecutive runs.
    var patternIdx = 0
    var forwardPositions = newSeq[int](lowerPattern.len)

    # Forward pass: find earliest match positions (greedy left-to-right)
    for i, c in lowerText:
      if patternIdx < lowerPattern.len and c == lowerPattern[patternIdx]:
        forwardPositions[patternIdx] = i
        inc patternIdx

    if patternIdx < lowerPattern.len:
      result = 0 # No match
    else:
      # Reverse pass: starting from the last forward-matched position, scan
      # backwards to find the latest possible match for each pattern char.
      # This pulls matches as close together (rightward) as possible,
      # maximizing consecutive runs.
      var reversePositions = newSeq[int](lowerPattern.len)
      var rIdx = lowerPattern.len - 1
      for i in countdown(forwardPositions[^1], 0):
        if rIdx >= 0 and lowerText[i] == lowerPattern[rIdx]:
          reversePositions[rIdx] = i
          dec rIdx

      # Score both sets of positions, take the best
      proc calcScore(positions: seq[int]): int =
        for j, pos in positions:
          if j > 0 and pos == positions[j - 1] + 1:
            result += 20 # Consecutive bonus
          else:
            result += 10
          # Bonus for matching near the start of the text
          result += max(0, 50 - pos * 5)

      let forwardScore = calcScore(forwardPositions)
      let reverseScore = calcScore(reversePositions)
      result = max(forwardScore, reverseScore)
