#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[unittest, options]
import pkg/results

import moepkg/rgb {.all.}

suite "hexToRgb":
  test "Parse hex color with prefix 1":
    check Rgb(red: 0, green: 0, blue: 0) == hexToRgb("#000000").get

  test "Parse hex color with prefix 2":
    check Rgb(red: 255, green: 255, blue: 255) == hexToRgb("#ffffff").get

  test "Parse hex color with prefix 3":
    check Rgb(red: 255, green: 0, blue: 0) == hexToRgb("#ff0000").get

  test "Parse hex color without prefix 1":
    check Rgb(red: 0, green: 0, blue: 0) == hexToRgb("000000").get

  test "Parse hex color without prefix 2":
    check Rgb(red: 255, green: 255, blue: 255) == hexToRgb("ffffff").get

  test "Parse hex without prefix 3":
    check Rgb(red: 255, green: 0, blue: 0) == hexToRgb("ff0000").get

  test "Invalid hex color 1":
    check hexToRgb("").isErr

  test "Invalid hex color 2":
    check hexToRgb("#").isErr

  test "Invalid hex color 3":
    check hexToRgb("#ff").isErr

  test "Invalid hex color 4":
    check hexToRgb("#ffffffffff").isErr

  test "Invalid hex color 5":
    check hexToRgb("#zzzzzz").isErr

suite "toHex":
  test "Rgb to hex string with prefix 1":
    check "#000000" == Rgb(red: 0, green: 0, blue: 0).toHex.get

  test "Rgb to hex string with prefix 2":
    check "#ffffff" == Rgb(red: 255, green: 255, blue: 255).toHex.get

  test "Rgb to hex string with prefix 3":
    check "#ff0000" == Rgb(red: 255, green: 0, blue: 0).toHex.get

  test "Rgb to hex string without prefix 1":
    check "000000" == Rgb(red: 0, green: 0, blue: 0).toHex(false).get

  test "Rgb to hex string without prefix 2":
    check "ffffff" == Rgb(red: 255, green: 255, blue: 255).toHex(false).get

  test "Rgb to hex string without prefix 3":
    check "ff0000" == Rgb(red: 255, green: 0, blue: 0).toHex(false).get

  test "TerminalDefaultRgb":
    check none(string) == Rgb(red: -1, green: -1, blue: -1).toHex

suite "isHexColor":
  test "isHexColor with prefix 1":
    check "#000000".isHexColor

  test "isHexColor with prefix 2":
    check "#ffffff".isHexColor

  test "isHexColor with prefix 3":
    check "#ff0000".isHexColor

  test "isHexColor without prefix 1":
    check "ff0000".isHexColor(false)

  test "isHexColor without prefix 2":
    check "ff0000".isHexColor(false)

  test "isHexColor without prefix 3":
    check "ff0000".isHexColor(false)

  test "Invalid value 1":
    check not "".isHexColor(false)

  test "Invalid value 2":
    check not "#ff".isHexColor(false)

  test "Invalid value 3":
    check not "ff".isHexColor(false)

  test "Invalid value 4":
    check not "00000000".isHexColor(false)

suite "inverseColor":
  test "inverseColor 1":
    check Rgb(red: 0, green: 0, blue: 0).inverseColor ==
      Rgb(red: 255, green: 255, blue: 255)

  test "inverseColor 2":
    check Rgb(red: 255, green: 255, blue: 255).inverseColor ==
      Rgb(red: 0, green: 0, blue: 0)

suite "calcRgbDifference":
  test "calcRgbDifference 1":
    check 3 == Rgb(red: 0, green: 0, blue: 0).calcRgbDifference(
      Rgb(red: 1, green: 1, blue: 1))

  test "calcRgbDifference 2":
    check 3 == Rgb(red: 1, green: 1, blue: 1).calcRgbDifference(
      Rgb(red: 0, green: 0, blue: 0))
