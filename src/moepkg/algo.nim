#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import unicodeext

proc fuzzyScore*(s1, s2: Runes): int =
  ## Calculate a score for Fuzzy search based on Smith–Waterman algorithm.

  const
    GapPenalty = -2
    MatchScore = 3
    MismatchPenalty = -1

  # Init matrix
  var matrix = newSeq[seq[int]](s1.len + 1)
  for i in 0 .. s1.len:
    matrix[i] = newSeq[int](s2.len + 1)

  for i in 0 .. s1.len:
    for j in 0 .. s2.len:
      if i == 0 or j == 0:
        matrix[i][j] = 0
      else:
        let
          score =
            if s1[i - 1] == s2[j - 1]: MatchScore
            else: MismatchPenalty
          match = matrix[i - 1][j - 1] + score
          delete = matrix[i - 1][j] + GapPenalty
          insert = matrix[i][j - 1] + GapPenalty
        matrix[i][j] = max(0, max(match, max(delete, insert)))

  var
    maxScore = 0
    maxI = 0
    maxJ = 0

  for i in 0 .. s1.len:
    for j in 0 .. s2.len:
      if matrix[i][j] > maxScore:
        maxScore = matrix[i][j]
        maxI = i
        maxJ = j

  var
    # Backtrack to find the aligned sequences
    alignedS1 = ""
    alignedS2 = ""

  while maxI > 0 and maxJ > 0 and matrix[maxI][maxJ] > 0:
    let
      currentScore = matrix[maxI][maxJ]
      diagonalScore = matrix[maxI - 1][maxJ - 1]
      leftScore = matrix[maxI][maxJ - 1]

    let score =
      if s1[maxI - 1] == s2[maxJ - 1]: MatchScore
      else: MismatchPenalty
    if currentScore == diagonalScore + score:
      alignedS1.add s1[maxI - 1]
      alignedS2.add s2[maxJ - 1]
      maxI -= 1
      maxJ -= 1
    elif currentScore == leftScore + GapPenalty:
      alignedS1.add '-'
      alignedS2.add s2[maxJ - 1]
      maxJ -= 1
    else:
      alignedS1.add s1[maxI - 1]
      alignedS2.add '-'
      maxI -= 1

  return maxScore
