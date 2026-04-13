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

import std/unittest

import ../src/moepkg/fuzzy_match

suite "fuzzyMatch":
  test "Exact match":
    check fuzzyMatch("hello", "hello") == true

  test "Prefix match":
    check fuzzyMatch("hel", "hello") == true

  test "Fuzzy match with gaps":
    check fuzzyMatch("hlo", "hello") == true

  test "Case insensitive match":
    check fuzzyMatch("HEL", "hello") == true
    check fuzzyMatch("hel", "HELLO") == true

  test "No match":
    check fuzzyMatch("xyz", "hello") == false

  test "Empty pattern matches everything":
    check fuzzyMatch("", "hello") == true

  test "Empty text matches nothing (except empty pattern)":
    check fuzzyMatch("a", "") == false
    check fuzzyMatch("", "") == true

  test "Pattern longer than text":
    check fuzzyMatch("helloworld", "hello") == false

  test "Match with underscore":
    check fuzzyMatch("my", "my_variable") == true
    check fuzzyMatch("mv", "my_variable") == true

suite "matchScore":
  test "Exact prefix match has high score":
    let score = matchScore("hel", "hello")
    check score >= 1000

  test "Case sensitive prefix match has bonus":
    let score1 = matchScore("Hel", "Hello")
    let score2 = matchScore("hel", "Hello")
    check score1 > score2

  test "Fuzzy match has lower score than prefix":
    let prefixScore = matchScore("hel", "hello")
    let fuzzyScore = matchScore("hlo", "hello")
    check prefixScore > fuzzyScore

  test "Empty pattern has zero score":
    let score = matchScore("", "hello")
    check score == 0

  test "No match has zero score":
    let score = matchScore("xyz", "hello")
    check score == 0

  test "Shorter words preferred for prefix match":
    let shortScore = matchScore("he", "he")
    let longScore = matchScore("he", "helicopter")
    check shortScore > longScore

  test "Consecutive character bonus":
    let consecutiveScore = matchScore("hel", "hello")
    let nonConsecutiveScore = matchScore("hlo", "hello")
    check consecutiveScore > nonConsecutiveScore
