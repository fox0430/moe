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

import std/unittest
import pkg/results

import moepkg/color {.all.}

suite "hexToRgb":
  test "Parse hex color 1":
    check Rgb(red: 0, green: 0, blue: 0) == hexToRgb("#000000").get

  test "Parse hex color 2":
    check Rgb(red: 255, green: 255, blue: 255) == hexToRgb("#ffffff").get

  test "Parse hex color 3":
    check Rgb(red: 255, green: 0, blue: 0) == hexToRgb("#ff0000").get

  test "Parse hex color 4":
    check Rgb(red: 0, green: 0, blue: 0) == hexToRgb("000000").get

  test "Parse hex color 5":
    check Rgb(red: 255, green: 255, blue: 255) == hexToRgb("ffffff").get

  test "Parse hex color 6":
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
