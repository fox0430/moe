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

## Which characters name a register. Kept free of dependencies so the key
## router can check the name typed after `"`.

proc isNamedRegisterName*(c: char): bool =
  ## Check if character is a valid named register name (a-z or A-Z)
  c in {'a' .. 'z', 'A' .. 'Z'}

proc isNumberRegisterName*(c: char): bool =
  ## Check if character is a valid number register name (0-9)
  c in {'0' .. '9'}

proc isSmallDeleteRegisterName*(c: char): bool =
  ## Check if character is the small delete register name (-)
  c == '-'

proc isPrimarySelectionRegisterName*(c: char): bool =
  ## Check if character is the primary selection register name (*)
  c == '*'

proc isClipboardSelectionRegisterName*(c: char): bool =
  ## Check if character is the clipboard selection register name (+, ~)
  c in {'+', '~'}

proc isClipboardRegisterName*(c: char): bool =
  ## Check if character is any clipboard register name (*, +, ~)
  c.isPrimarySelectionRegisterName or c.isClipboardSelectionRegisterName

proc isBlackHoleRegisterName*(c: char): bool =
  ## Check if character is the black hole register name (_)
  c == '_'

proc isValidRegisterName*(c: char): bool =
  ## Check if character is any valid register name
  c.isNamedRegisterName or c.isNumberRegisterName or c.isSmallDeleteRegisterName or
    c.isClipboardRegisterName or c.isBlackHoleRegisterName or c == '"'
