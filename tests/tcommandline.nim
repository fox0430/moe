#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import std/[unittest, strutils, importutils, deques]

import pkg/results

import moepkg/[unicodeext, editorview]

import moepkg/commandline {.all.}

suite "commandline: calcWindowaHeight":
  var c: CommandLine

  setup:
    c = initCommandLine().get

  test "Empty buffer":
    c.w = 100
    c.buffer = ru""

    check 1 == c.calcWindowaHeight

  test "Width is 0":
    c.w = 0
    c.buffer = ru""

    check 1 == c.calcWindowaHeight

  test "Basic":
    c.w = 100
    c.buffer = ru"abc"

    check 1 == c.calcWindowaHeight

  test "Only prompt":
    c.w = 100
    c.setPrompt ru":"

    check 1 == c.calcWindowaHeight

  test "With prompt":
    c.w = 100
    c.setPrompt ru":"
    c.buffer = ru"abc"

    check 1 == c.calcWindowaHeight

  test "Height is 2":
    c.w = 50
    c.setPrompt ru":"
    c.buffer = "a".repeat(60).toRunes

    check 2 == c.calcWindowaHeight

  test "Use newWinHeight":
    c.w = 100
    c.setPrompt ru":"
    c.buffer = "a".repeat(60).toRunes

    assert 1 == c.calcWindowaHeight

    check 2 == c.calcWindowaHeight(50)

suite "commandline: resize":
  privateAccess CommandLine

  var c: CommandLine

  setup:
    c = initCommandLine().get

  test "Height is 0":
    c.buffer = "".repeat(60).toRunes
    c.resize(0, 0, 1, 0)

    check 0 == c.y
    check 0 == c.x
    check 1 == c.h
    check 0 == c.w

    check c.view.originalLine.len == 1

    check c.isUpdate

  test "Width is 0":
    c.buffer = "".repeat(60).toRunes
    c.resize(0, 0, 0, 1)

    check 0 == c.y
    check 0 == c.x
    check 0 == c.h
    check 1 == c.w

    check c.view.originalLine.len == 0

    check c.isUpdate

  test "Empty buffer":
    c.buffer = ru""
    c.resize(0, 0, 1, 100)

    check 0 == c.y
    check 0 == c.x
    check 1 == c.h
    check 100 == c.w

    check c.view.originalLine.len == 1

    check c.isUpdate

  test "Basic":
    c.buffer = "a".repeat(60).toRunes
    c.resize(0, 0, 2, 50)

    check 0 == c.y
    check 0 == c.x
    check 2 == c.h
    check 50 == c.w

    check c.view.originalLine.len == 2

    check c.isUpdate
