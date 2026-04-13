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
    # Fuzzy match score based on character positions
    var score = 0
    var patternIdx = 0
    var lastMatchPos = -1

    for i, c in lowerText:
      if patternIdx < lowerPattern.len and c == lowerPattern[patternIdx]:
        # Bonus for consecutive matches
        if lastMatchPos == i - 1:
          score += 20
        else:
          score += 10
        lastMatchPos = i
        inc patternIdx

    if patternIdx >= lowerPattern.len:
      result = score
    else:
      result = 0 # No match
