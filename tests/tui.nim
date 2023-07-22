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

import moepkg/ui {.all.}

suite "ColorMode to string":
  test "from ColorMode.none":
    check "none" == $ColorMode.none

  test "from ColorMode.c8":
    check "8" == $ColorMode.c8

  test "from ColorMode.c16":
    check "16" == $ColorMode.c16

  test "from ColorMode.c256":
    check "256" == $ColorMode.c256

  test "from ColorMode.c24bit":
    check "24bit" == $ColorMode.c24bit

suite "parseColorMode":
  test "none":
    check ColorMode.none == "none".parseColorMode.get

  test "c8":
    check ColorMode.c8 == "8".parseColorMode.get

  test "c16":
    check ColorMode.c16 == "16".parseColorMode.get

  test "c256":
    check ColorMode.c256 == "256".parseColorMode.get

  test "c24bit":
    check ColorMode.c24bit == "24bit".parseColorMode.get
