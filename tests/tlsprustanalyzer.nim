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

import std/[unittest, json]

import moepkg/lsp/serverspecifics/rustanalyzer {.all.}

suite "experimentClientCapabilities":
  test "Disable experimental":
    check experimentClientCapabilities(RustAnalyzerConfigs()) == %*{
      "commands": {
        "commands": []
      }
    }

  test "Enable rust-analyzer.runSingle":
    check experimentClientCapabilities(RustAnalyzerConfigs(
      runSingle: true
    )) == %*{
      "commands": {
        "commands": [
          "rust-analyzer.runSingle"
        ]
      }
    }

  test "Enable rust-analyzer.debugSingle":
    check experimentClientCapabilities(RustAnalyzerConfigs(
      debugSingle: true
    )) == %*{
      "commands": {
        "commands": [
          "rust-analyzer.debugSingle"
        ]
      }
    }

  test "Enable all":
    check experimentClientCapabilities(RustAnalyzerConfigs(
      runSingle: true,
      debugSingle: true
    )) == %*{
      "commands": {
        "commands": [
          "rust-analyzer.runSingle",
          "rust-analyzer.debugSingle"
        ]
      }
    }
