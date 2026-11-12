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

import
  std/[unittest, json, options, strutils, os, tables, envvars, math, strformat, times]

import pkg/results

import ../src/moepkg/color {.all.}
import ../src/moepkg/theme
import ../src/moepkg/vscode_theme {.all.}

import config_test_helper

const UnreadableContrast = 2.0
  ## Below this WCAG contrast ratio text cannot be read. Above it a palette may
  ## dim text on purpose (hidden files, inlay hints).

const RecedingEntries =
  ColorBgOnlyEntries + {
    EditorColorPairIndex.whitespace, EditorColorPairIndex.indentationLine,
    EditorColorPairIndex.scrollBarThumb, EditorColorPairIndex.scrollBarTrack,
  } ## Entries whose foreground is never drawn or is meant to recede.

proc contrastRatio(a, b: Rgb): float =
  ## WCAG 2 contrast ratio, from 1 to 21.
  proc luminance(c: Rgb): float =
    proc channel(v: int16): float =
      let s = v.float / 255
      if s <= 0.03928:
        s / 12.92
      else:
        pow((s + 0.055) / 1.055, 2.4)

    0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue)

  let (x, y) = (luminance(a), luminance(b))
  (max(x, y) + 0.05) / (min(x, y) + 0.05)

proc unreadablePairs(colors: ThemeColors): seq[string] =
  ## The entries whose text cannot be read on their background.
  for i in EditorColorPairIndex:
    let (fg, bg) = (colors[i].foreground.rgb, colors[i].background.rgb)
    if i in RecedingEntries or fg.isTermDefaultColor or bg.isTermDefaultColor:
      continue
    let ratio = contrastRatio(fg, bg)
    if ratio < UnreadableContrast:
      result.add fmt"{i}: {fg.toHex.get} on {bg.toHex.get} ({ratio:.1f}:1)"

suite "vscode_theme - VsCodeFlavor enum":
  test "enum values":
    check $VsCodeFlavor.VSCodium == "VSCodium"
    check $VsCodeFlavor.CodeOss == "CodeOss"
    check $VsCodeFlavor.VSCode == "VSCode"

suite "vscode_theme - parseVsColor":
  test "#RRGGBB":
    let c = parseVsColor("#1a2b3c")
    require c.isSome
    check c.get.rgb == Rgb(red: 0x1a, green: 0x2b, blue: 0x3c)
    check c.get.alpha == 1.0

  test "#RRGGBBAA keeps the alpha":
    let c = parseVsColor("#ff000080")
    require c.isSome
    check c.get.rgb == Rgb(red: 255, green: 0, blue: 0)
    check abs(c.get.alpha - 0x80 / 255) < 1e-9

  test "short forms":
    check parseVsColor("#f80").get.rgb == Rgb(red: 0xff, green: 0x88, blue: 0x00)
    check parseVsColor("#f808").get.alpha == 0x88 / 255

  test "invalid strings":
    for s in ["", "ff0000", "#gggggg", "#12345", "#1234567890"]:
      checkpoint s
      check parseVsColor(s).isNone

suite "vscode_theme - blend":
  test "opaque is unchanged":
    let c = Rgba(rgb: Rgb(red: 1, green: 2, blue: 3), alpha: 1.0)
    check c.blend(Rgb(red: 255, green: 255, blue: 255)) == c.rgb

  test "translucent mixes with what is under it":
    # VS Code Light's whitespace (#33333333) on white.
    let c = parseVsColor("#33333333").get
    check c.blend(Rgb(red: 255, green: 255, blue: 255)) ==
      Rgb(red: 0xd6, green: 0xd6, blue: 0xd6)

suite "vscode_theme - themeEntry":
  test "found when theme label matches":
    let json = %*{
      "contributes": {
        "themes": [
          {"label": "Dark+ (default dark)", "path": "./themes/dark_plus.json"},
          {"label": "Light+ (default light)", "path": "./themes/light_plus.json"},
        ]
      }
    }
    check json.themeEntry("Dark+ (default dark)"){"path"}.getStr ==
      "./themes/dark_plus.json"
    check json.themeEntry("Light+ (default light)"){"path"}.getStr ==
      "./themes/light_plus.json"

  test "none when theme label does not match":
    let json = %*{
      "contributes": {
        "themes": [{"label": "Dark+ (default dark)", "path": "./themes/dark_plus.json"}]
      }
    }
    check json.themeEntry("Monokai") == nil

  test "none when contributes is missing":
    let json = %*{"name": "some-extension"}
    check json.themeEntry("Dark+") == nil

  test "none when themes array is missing":
    let json = %*{"contributes": {"languages": []}}
    check json.themeEntry("Dark+") == nil

  test "none when themes is not an array":
    let json = %*{"contributes": {"themes": "not an array"}}
    check json.themeEntry("Dark+") == nil

  test "found when theme id matches":
    let json = %*{
      "contributes": {
        "themes": [
          {
            "label": "%darkModernThemeLabel%",
            "id": "Default Dark Modern",
            "path": "./themes/dark_modern.json",
          }
        ]
      }
    }
    check json.themeEntry("Default Dark Modern") != nil

  test "found when theme id matches but label is NLS placeholder":
    let json = %*{
      "contributes": {
        "themes": [
          {
            "label": "%darkPlusColorThemeLabel%",
            "id": "Default Dark+",
            "path": "./themes/dark_plus.json",
          }
        ]
      }
    }
    check json.themeEntry("Default Dark+") != nil

  test "none when theme has no label or id":
    let json = %*{"contributes": {"themes": [{"path": "./themes/dark.json"}]}}
    check json.themeEntry("Dark+") == nil

  test "of two entries for the theme, the first gives both its file and its kind":
    let json = %*{
      "contributes": {
        "themes": [
          {"id": "T", "path": "./dark.json"},
          {"label": "T", "uiTheme": "vs", "path": "./light.json"},
        ]
      }
    }
    let entry = json.themeEntry("T")
    check entry{"path"}.getStr == "./dark.json"
    check entry.themeKind == vtkDark

suite "vscode_theme - makeColorThemeFromVSCodeThemeFile":
  test "basic theme with editor foreground and background":
    let themeJson = %*{
      "colors": {"editor.foreground": "#d4d4d4", "editor.background": "#1e1e1e"},
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    # Check foreground is applied to default
    check result[EditorColorPairIndex.default].foreground.rgb.red == 0xd4
    check result[EditorColorPairIndex.default].foreground.rgb.green == 0xd4
    check result[EditorColorPairIndex.default].foreground.rgb.blue == 0xd4

    # Check background is applied to default
    check result[EditorColorPairIndex.default].background.rgb.red == 0x1e
    check result[EditorColorPairIndex.default].background.rgb.green == 0x1e
    check result[EditorColorPairIndex.default].background.rgb.blue == 0x1e

  test "keyword token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [{"scope": "keyword", "settings": {"foreground": "#569cd6"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.keyword].foreground.rgb.red == 0x56
    check result[EditorColorPairIndex.keyword].foreground.rgb.green == 0x9c
    check result[EditorColorPairIndex.keyword].foreground.rgb.blue == 0xd6

  test "string token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [{"scope": "string", "settings": {"foreground": "#ce9178"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.stringLit].foreground.rgb.red == 0xce
    check result[EditorColorPairIndex.stringLit].foreground.rgb.green == 0x91
    check result[EditorColorPairIndex.stringLit].foreground.rgb.blue == 0x78
    # Also affects charLit and lspString
    check result[EditorColorPairIndex.charLit].foreground.rgb ==
      result[EditorColorPairIndex.stringLit].foreground.rgb

  test "comment token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [{"scope": "comment", "settings": {"foreground": "#6a9955"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.comment].foreground.rgb.red == 0x6a
    check result[EditorColorPairIndex.comment].foreground.rgb.green == 0x99
    check result[EditorColorPairIndex.comment].foreground.rgb.blue == 0x55
    # Also affects longComment
    check result[EditorColorPairIndex.longComment].foreground.rgb ==
      result[EditorColorPairIndex.comment].foreground.rgb

  test "constant.numeric token color affects all number types":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "constant.numeric", "settings": {"foreground": "#b5cea8"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    let expectedRgb = Rgb(red: 0xb5, green: 0xce, blue: 0xa8)
    check result[EditorColorPairIndex.binNumber].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.decNumber].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.floatNumber].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.hexNumber].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.octNumber].foreground.rgb == expectedRgb

  test "entity.name.function token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "entity.name.function", "settings": {"foreground": "#dcdcaa"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    let expectedRgb = Rgb(red: 0xdc, green: 0xdc, blue: 0xaa)
    check result[EditorColorPairIndex.functionName].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.function].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.`method`].foreground.rgb == expectedRgb

  test "entity.name.type token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "entity.name.type", "settings": {"foreground": "#4ec9b0"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    let expectedRgb = Rgb(red: 0x4e, green: 0xc9, blue: 0xb0)
    check result[EditorColorPairIndex.typeName].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.className].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.interfaceName].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.builtinType].foreground.rgb == expectedRgb

  test "variable token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [{"scope": "variable", "settings": {"foreground": "#9cdcfe"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    let expectedRgb = Rgb(red: 0x9c, green: 0xdc, blue: 0xfe)
    check result[EditorColorPairIndex.specialVar].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.variable].foreground.rgb == expectedRgb

  test "line number colors":
    let themeJson = %*{
      "colors": {
        "editorLineNumber.foreground": "#858585",
        "editorLineNumber.activeForeground": "#c6c6c6",
      },
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.lineNum].foreground.rgb.red == 0x85
    check result[EditorColorPairIndex.lineNum].foreground.rgb.green == 0x85
    check result[EditorColorPairIndex.lineNum].foreground.rgb.blue == 0x85

    check result[EditorColorPairIndex.currentLineNum].foreground.rgb.red == 0xc6
    check result[EditorColorPairIndex.currentLineNum].foreground.rgb.green == 0xc6
    check result[EditorColorPairIndex.currentLineNum].foreground.rgb.blue == 0xc6

  test "status bar colors":
    let themeJson = %*{
      "colors": {"statusBar.foreground": "#ffffff", "statusBar.background": "#007acc"},
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    # Check status bar foreground
    check result[EditorColorPairIndex.statusLineNormalMode].foreground.rgb ==
      Rgb(red: 255, green: 255, blue: 255)

    # Check status bar background
    check result[EditorColorPairIndex.statusLineNormalMode].background.rgb.red == 0x00
    check result[EditorColorPairIndex.statusLineNormalMode].background.rgb.green == 0x7a
    check result[EditorColorPairIndex.statusLineNormalMode].background.rgb.blue == 0xcc

  test "tab colors":
    let themeJson = %*{
      "colors": {
        "tab.inactiveForeground": "#888888",
        "tab.inactiveBackground": "#2d2d2d",
        "tab.activeForeground": "#ffffff",
        "tab.activeBackground": "#1e1e1e",
      },
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.tab].foreground.rgb.red == 0x88
    check result[EditorColorPairIndex.tab].background.rgb.red == 0x2d
    check result[EditorColorPairIndex.currentTab].foreground.rgb.red == 0xff
    check result[EditorColorPairIndex.currentTab].background.rgb.red == 0x1e

  test "selection background":
    let themeJson =
      %*{"colors": {"editor.selectionBackground": "#264f78"}, "tokenColors": []}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.selectArea].background.rgb.red == 0x26
    check result[EditorColorPairIndex.selectArea].background.rgb.green == 0x4f
    check result[EditorColorPairIndex.selectArea].background.rgb.blue == 0x78

  test "search highlight":
    let themeJson = %*{
      "colors": {"editor.findMatchHighlightBackground": "#ea5c0055"}, "tokenColors": []
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    # Blended onto VS Code's dark editor background (#1e1e1e).
    check result[EditorColorPairIndex.searchResult].background.rgb ==
      Rgb(red: 0x62, green: 0x33, blue: 0x14)

  test "current line background":
    let themeJson =
      %*{"colors": {"editor.lineHighlightBackground": "#ffffff0a"}, "tokenColors": []}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    # Blended onto VS Code's dark editor background (#1e1e1e).
    check result[EditorColorPairIndex.currentLineBg].background.rgb ==
      Rgb(red: 0x27, green: 0x27, blue: 0x27)

  test "a cleared current line background highlights with the border":
    let c = makeColorThemeFromVSCodeThemeFile(
      %*{
        "colors": {
          "editor.lineHighlightBackground": "#00000000",
          "editor.lineHighlightBorder": "#3a3a3a",
        }
      }
    )
    for index in [
      EditorColorPairIndex.currentLineBg, EditorColorPairIndex.currentColumnBg
    ]:
      check c[index].background.rgb == rgb("#3a3a3a")

  test "a cleared current line background takes VS Code's default border":
    let c = makeColorThemeFromVSCodeThemeFile(
      %*{"colors": {"editor.lineHighlightBackground": "#00000000"}}
    )
    check c[EditorColorPairIndex.currentLineBg].background.rgb == rgb("#282828")

  test "a theme that clears the background and the border shows no highlight":
    let c = makeColorThemeFromVSCodeThemeFile(
      %*{
        "colors": {
          "editor.lineHighlightBackground": "#00000000",
          "editor.lineHighlightBorder": "#00000000",
        }
      }
    )
    check c[EditorColorPairIndex.currentLineBg].background.rgb == rgb("#1e1e1e")

  test "high contrast keeps moe's highlight when the background is cleared":
    let c = makeColorThemeFromVSCodeThemeFile(
      %*{"colors": {"editor.lineHighlightBackground": "#00000000"}}, vtkHcDark
    )
    check c[EditorColorPairIndex.currentLineBg] ==
      DefaultColors[EditorColorPairIndex.currentLineBg]

  test "translucent status bar text is blended onto the status bar":
    let c = makeColorThemeFromVSCodeThemeFile(
      %*{
        "colors":
          {"statusBar.foreground": "#ffffff80", "statusBar.background": "#007acc"}
      }
    )
    check c[EditorColorPairIndex.statusLineNormalMode].foreground.rgb == rgb("#80bde6")

  test "a translucent selected item is blended onto the suggest widget":
    let c = makeColorThemeFromVSCodeThemeFile(
      %*{
        "colors": {
          "editorSuggestWidget.background": "#336699",
          "editorSuggestWidget.selectedBackground": "#ffffff80",
        }
      }
    )
    check c[EditorColorPairIndex.popupWinCurrentLine].background.rgb == rgb("#99b3cc")

  test "error and warning colors":
    let themeJson = %*{
      "colors": {
        "editorError.foreground": "#f14c4c",
        "editorWarning.foreground": "#cca700",
        "editorInfo.foreground": "#3794ff",
      },
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.errorMessage].foreground.rgb.red == 0xf1
    check result[EditorColorPairIndex.syntaxCheckErr].foreground.rgb.red == 0xf1

    check result[EditorColorPairIndex.warnMessage].foreground.rgb.red == 0xcc
    check result[EditorColorPairIndex.syntaxCheckWarn].foreground.rgb.red == 0xcc

    check result[EditorColorPairIndex.syntaxCheckInfo].foreground.rgb.red == 0x37

  test "git decoration colors":
    let themeJson = %*{
      "colors": {
        "gitDecoration.addedResourceForeground": "#81b88b",
        "gitDecoration.deletedResourceForeground": "#c74e39",
        "gitDecoration.modifiedResourceForeground": "#e2c08d",
      },
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.diffViewerAddedLine].foreground.rgb.red == 0x81
    check result[EditorColorPairIndex.sidebarGitAddedSign].foreground.rgb.red == 0x81

    check result[EditorColorPairIndex.diffViewerDeletedLine].foreground.rgb.red == 0xc7
    check result[EditorColorPairIndex.sidebarGitDeletedSign].foreground.rgb.red == 0xc7

    check result[EditorColorPairIndex.sidebarGitChangedSign].foreground.rgb.red == 0xe2

  test "whitespace foreground":
    let themeJson =
      %*{"colors": {"editorWhitespace.foreground": "#e3e4e229"}, "tokenColors": []}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    # Blended onto VS Code's dark editor background (#1e1e1e).
    check result[EditorColorPairIndex.whitespace].foreground.rgb ==
      Rgb(red: 0x3e, green: 0x3e, blue: 0x3e)

  test "scope array in tokenColors":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [
        {"scope": ["keyword", "keyword.control"], "settings": {"foreground": "#c586c0"}}
      ],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.keyword].foreground.rgb.red == 0xc5
    check result[EditorColorPairIndex.keyword].foreground.rgb.green == 0x86
    check result[EditorColorPairIndex.keyword].foreground.rgb.blue == 0xc0

  test "entity scope affects function and type":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [{"scope": "entity", "settings": {"foreground": "#4fc1ff"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    let expectedRgb = Rgb(red: 0x4f, green: 0xc1, blue: 0xff)
    check result[EditorColorPairIndex.functionName].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.typeName].foreground.rgb == expectedRgb

  test "booleans are language constants, builtins library functions":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [
        {"scope": "constant.language", "settings": {"foreground": "#569cd6"}},
        {"scope": "support.function", "settings": {"foreground": "#dcdcaa"}},
        {"scope": "entity.name.tag", "settings": {"foreground": "#ff0000"}},
      ],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.boolean].foreground.rgb == rgb("#569cd6")
    check result[EditorColorPairIndex.builtin].foreground.rgb == rgb("#dcdcaa")

  test "constant scope affects numbers":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [{"scope": "constant", "settings": {"foreground": "#b5cea8"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    let expectedRgb = Rgb(red: 0xb5, green: 0xce, blue: 0xa8)
    check result[EditorColorPairIndex.binNumber].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.decNumber].foreground.rgb == expectedRgb

  test "operator token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "keyword.operator", "settings": {"foreground": "#d4d4d4"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.operator].foreground.rgb.red == 0xd4

  test "namespace token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "entity.name.namespace", "settings": {"foreground": "#4ec9b0"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.namespace].foreground.rgb.red == 0x4e

  test "decorator token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [
        {
          "scope": "entity.name.function.decorator",
          "settings": {"foreground": "#dcdcaa"},
        }
      ],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.decorator].foreground.rgb.red == 0xdc
    check result[EditorColorPairIndex.attribute].foreground.rgb.red == 0xdc

  test "preprocessor token color from keyword.control.directive":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "keyword.control.directive", "settings": {"foreground": "#c586c0"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.preprocessor].foreground.rgb.red == 0xc5

  test "preprocessor token color from meta.preprocessor":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "meta.preprocessor", "settings": {"foreground": "#569cd6"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.preprocessor].foreground.rgb.red == 0x56

  test "macro token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "entity.name.function.macro", "settings": {"foreground": "#dcdcaa"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.`macro`].foreground.rgb.red == 0xdc

  test "enum token colors":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [
        {"scope": "entity.name.type.enum", "settings": {"foreground": "#4ec9b0"}},
        {"scope": "variable.other.enummember", "settings": {"foreground": "#4fc1ff"}},
      ],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.enumName].foreground.rgb.red == 0x4e
    check result[EditorColorPairIndex.enumMember].foreground.rgb.red == 0x4f

  test "property token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "variable.other.property", "settings": {"foreground": "#9cdcfe"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.property].foreground.rgb.red == 0x9c

  test "parameter token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "variable.parameter", "settings": {"foreground": "#9cdcfe"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.parameter].foreground.rgb.red == 0x9c

  test "inlay hints colors":
    let themeJson = %*{
      "colors": {
        "editorInlayHint.foreground": "#969696", "editorInlayHint.background": "#1e1e1e"
      },
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.inlayHint].foreground.rgb.red == 0x96
    check result[EditorColorPairIndex.inlayHint].background.rgb.red == 0x1e

  test "code lens color":
    let themeJson =
      %*{"colors": {"editorCodeLens.foreground": "#999999"}, "tokenColors": []}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.codeLens].foreground.rgb.red == 0x99

  test "a manager's current line is the selected list item":
    let themeJson = %*{
      "colors": {
        "list.activeSelectionForeground": "#ffffff",
        "list.activeSelectionBackground": "#094771",
      },
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    for index in [
      EditorColorPairIndex.backupManagerCurrentLine,
      EditorColorPairIndex.recoveryManagerCurrentLine,
      EditorColorPairIndex.configModeCurrentLine,
    ]:
      check result[index].foreground.rgb == rgb("#ffffff")
      check result[index].background.rgb == rgb("#094771")

  test "the current line number is the active line number color, not the cursor's":
    let themeJson = %*{
      "colors": {
        "editorCursor.foreground": "#528bff",
        "editorLineNumber.activeForeground": "#ffd700",
      },
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.currentLineNum].foreground.rgb == rgb("#ffd700")

    let unset = makeColorThemeFromVSCodeThemeFile(
      %*{"colors": {"editorCursor.foreground": "#528bff"}, "tokenColors": []}
    )
    # VS Code's dark default for it.
    check unset[EditorColorPairIndex.currentLineNum].foreground.rgb == rgb("#c6c6c6")

  test "popup window colors":
    let themeJson = %*{
      "colors": {
        "editorSuggestWidget.foreground": "#d4d4d4",
        "editorSuggestWidget.background": "#252526",
        "editorSuggestWidget.highlightForeground": "#0097fb",
        "editorSuggestWidget.selectedForeground": "#ffffff",
        "editorSuggestWidget.selectedBackground": "#094771",
      },
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.popupWindow].foreground.rgb.red == 0xd4
    check result[EditorColorPairIndex.popupWindow].background.rgb.red == 0x25
    # highlightForeground colors matched characters, not the selected item.
    check result[EditorColorPairIndex.popupWinCurrentLine].foreground.rgb.red == 0xff
    check result[EditorColorPairIndex.popupWinCurrentLine].background.rgb.red == 0x09

  test "git conflict color":
    let themeJson = %*{
      "colors": {"gitDecoration.conflictingResourceForeground": "#e4676b"},
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.gitConflict].foreground.rgb.red == 0xe4

  test "hyperlink token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "markup.underline.link", "settings": {"foreground": "#3794ff"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.dir].foreground.rgb.red == 0x37
    check result[EditorColorPairIndex.pcLink].foreground.rgb.red == 0x37

  test "blank highlights keep moe's own, visible on the editor background":
    # Dark Modern's tab.activeBorder is its editor background.
    let themeJson = %*{
      "colors": {"editor.background": "#1f1f1f", "tab.activeBorder": "#1f1f1f"},
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    for index in [
      EditorColorPairIndex.highlightFullWidthSpace,
      EditorColorPairIndex.highlightTrailingSpaces,
    ]:
      check result[index].background == DefaultColors[index].background

  test "line number background":
    let themeJson =
      %*{"colors": {"editorLineNumber.background": "#1e1e1e"}, "tokenColors": []}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.lineNum].background.rgb.red == 0x1e

  test "resolveThemeIncludes merges colors and tokenColors":
    # Simulate include chain: child includes base
    let baseDir = getTempDir() / "moe_test_theme_include"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    # Write base theme
    let baseTheme = %*{
      "colors": {"editor.foreground": "#aaaaaa", "editor.background": "#111111"},
      "tokenColors": [{"scope": "comment", "settings": {"foreground": "#6a9955"}}],
    }
    writeFile(baseDir / "base.json", $baseTheme)

    # Child theme overrides foreground and adds keyword token
    let childTheme = %*{
      "include": "./base.json",
      "colors": {"editor.foreground": "#cccccc"},
      "tokenColors": [{"scope": "keyword", "settings": {"foreground": "#569cd6"}}],
    }

    let resolved = resolveThemeIncludes(childTheme, baseDir)
    require resolved.isOk
    let result = makeColorThemeFromVSCodeThemeFile(resolved.get)

    # Child overrides foreground
    check result[EditorColorPairIndex.default].foreground.rgb ==
      Rgb(red: 0xcc, green: 0xcc, blue: 0xcc)
    # Base provides background
    check result[EditorColorPairIndex.default].background.rgb ==
      Rgb(red: 0x11, green: 0x11, blue: 0x11)
    # Base provides comment color
    check result[EditorColorPairIndex.comment].foreground.rgb ==
      Rgb(red: 0x6a, green: 0x99, blue: 0x55)
    # Child provides keyword color
    check result[EditorColorPairIndex.keyword].foreground.rgb ==
      Rgb(red: 0x56, green: 0x9c, blue: 0xd6)

  test "empty dark theme: VS Code's dark defaults on moe's dark colors":
    let themeJson = %*{"colors": {}, "tokenColors": []}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.default].foreground.rgb == rgb("#bbbbbb")
    check result[EditorColorPairIndex.default].background.rgb == rgb("#1e1e1e")
    check result[EditorColorPairIndex.statusLineNormalMode].foreground.rgb ==
      rgb("#ffffff")
    check result[EditorColorPairIndex.statusLineNormalMode].background.rgb ==
      rgb("#007acc")
    # No VS Code color for it: moe's own, on the editor background.
    check result[EditorColorPairIndex.filerDirectory].foreground ==
      DefaultColors[EditorColorPairIndex.filerDirectory].foreground

  test "missing tokenColors key":
    let themeJson = %*{"colors": {"editor.foreground": "#ffffff"}}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.default].foreground.rgb.red == 0xff

  test "tokenColors with nil settings is skipped":
    let themeJson = %*{"colors": {}, "tokenColors": [{"scope": "keyword"}]}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    # Should not crash; no usable rule means the editor foreground.
    check result[EditorColorPairIndex.keyword].foreground.rgb == rgb("#bbbbbb")

  test "unnamed scope with bracketsForeground":
    let themeJson =
      %*{"colors": {}, "tokenColors": [{"settings": {"bracketsForeground": "#ffd700"}}]}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.parenPair].foreground.rgb.red == 0xff
    check result[EditorColorPairIndex.parenPair].foreground.rgb.green == 0xd7
    check result[EditorColorPairIndex.parenPair].foreground.rgb.blue == 0x00

  test "a null or empty scope is unscoped too":
    for scope in [newJNull(), %""]:
      let themeJson = %*{
        "colors": {},
        "tokenColors": [{"scope": scope, "settings": {"bracketsForeground": "#ffd700"}}],
      }
      let result = makeColorThemeFromVSCodeThemeFile(themeJson)
      checkpoint $scope
      check result[EditorColorPairIndex.parenPair].foreground.rgb == rgb("#ffd700")

  test "unscoped rule without bracketsForeground":
    # Many themes open tokenColors with such a global rule.
    let themeJson =
      %*{"colors": {}, "tokenColors": [{"settings": {"foreground": "#ff0000"}}]}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    # Selected text's color: the pair's background is the selection.
    check result[EditorColorPairIndex.parenPair].foreground.rgb == rgb("#bbbbbb")

  test "tokenColors naming a separate file":
    # VS Code also takes a path to a .tmTheme or .json file here.
    let themeJson = %*{"colors": {}, "tokenColors": "./theme.tmTheme"}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.keyword].foreground.rgb == rgb("#bbbbbb")

  test "a later rule for a scope overrides only what it sets":
    # A derived theme italicizing comments its include colors.
    let themeJson = %*{
      "colors": {},
      "tokenColors": [
        {"scope": "comment", "settings": {"foreground": "#6a9955"}},
        {"scope": "comment", "settings": {"fontStyle": "italic"}},
      ],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.comment].foreground.rgb == rgb("#6a9955")

  test "a rule without a foreground inherits its parent's":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [
        {"scope": "keyword", "settings": {"foreground": "#c586c0"}},
        {"scope": "keyword.operator", "settings": {"fontStyle": "bold"}},
      ],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.operator].foreground.rgb == rgb("#c586c0")

  test "comma-separated scope string":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [
        {
          "scope": "constant.character, constant.other",
          "settings": {"foreground": "#ae81ff"},
        }
      ],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.escapeSequence].foreground.rgb == rgb("#ae81ff")
    check result[EditorColorPairIndex.constParameter].foreground.rgb == rgb("#ae81ff")

  test "every syntax entry follows a rule or the editor foreground":
    let themeJson = %*{"colors": {"editor.foreground": "#123456"}, "tokenColors": []}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    for index in TokenColorIndexes:
      check result[index].foreground.rgb == rgb("#123456")

  test "specific kinds of type and function take their own scopes first":
    proc rule(scope, fg: string): JsonNode =
      %*{"scope": scope, "settings": {"foreground": fg}}

    let themeJson = %*{
      "colors": {},
      "tokenColors": [
        rule("entity.name.type", "#000001"),
        rule("entity.name.type.class", "#000002"),
        rule("entity.name.type.interface", "#000003"),
        rule("entity.name.function", "#000004"),
        rule("entity.name.function.member", "#000005"),
        rule("support.type.primitive", "#000006"),
        rule("meta.attribute", "#000007"),
        rule("entity.name.function.decorator", "#000008"),
      ],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    type I = EditorColorPairIndex
    check result[I.typeName].foreground.rgb == rgb("#000001")
    check result[I.className].foreground.rgb == rgb("#000002")
    check result[I.interfaceName].foreground.rgb == rgb("#000003")
    check result[I.function].foreground.rgb == rgb("#000004")
    check result[I.`method`].foreground.rgb == rgb("#000005")
    check result[I.builtinType].foreground.rgb == rgb("#000006")
    check result[I.attribute].foreground.rgb == rgb("#000007")
    check result[I.decorator].foreground.rgb == rgb("#000008")

  test "selectors that need a context are not applied":
    let themeJson = %*{
      "colors": {"editor.foreground": "#123456"},
      "tokenColors": [
        {
          "scope": "source.ts keyword.operator.new",
          "settings": {"foreground": "#ff0000"},
        },
        {
          "scope": "constant.numeric.line-number.find-in-files - match",
          "settings": {"foreground": "#00ff00"},
        },
      ],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.keyword].foreground.rgb == rgb("#123456")
    check result[EditorColorPairIndex.decNumber].foreground.rgb == rgb("#123456")

  test "rust-analyzer entries take their scopes' colors":
    proc rule(scope, fg: string): JsonNode =
      %*{"scope": scope, "settings": {"foreground": fg}}

    let themeJson = %*{
      "colors": {},
      "tokenColors": [
        rule("string", "#000001"),
        rule("constant.character.escape", "#000002"),
        rule("invalid", "#000003"),
        rule("string.regexp", "#000004"),
        rule("variable.language", "#000005"),
        rule("entity.name.label", "#000006"),
        rule("storage.modifier", "#000007"),
        rule("keyword.operator", "#000008"),
        rule("keyword.operator.logical", "#000009"),
        rule("entity.name.type", "#00000a"),
      ],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    type I = EditorColorPairIndex
    check result[I.escapeSequence].foreground.rgb == rgb("#000002")
    check result[I.invalidEscapeSequence].foreground.rgb == rgb("#000003")
    check result[I.formatSpecifier].foreground.rgb == rgb("#000001")
    check result[I.regexp].foreground.rgb == rgb("#000004")
    check result[I.selfKeyword].foreground.rgb == rgb("#000005")
    check result[I.label].foreground.rgb == rgb("#000006")
    check result[I.lifetime].foreground.rgb == rgb("#000007")
    check result[I.arithmetic].foreground.rgb == rgb("#000008")
    check result[I.colon].foreground.rgb == rgb("#000008")
    check result[I.logical].foreground.rgb == rgb("#000009")
    check result[I.typeParameter].foreground.rgb == rgb("#00000a")
    check result[I.typeAlias].foreground.rgb == rgb("#00000a")

  test "an invalid escape without an invalid rule looks like an escape":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "constant.character.escape", "settings": {"foreground": "#d7ba7d"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.invalidEscapeSequence].foreground.rgb ==
      rgb("#d7ba7d")

suite "vscode_theme - findTokenSettings":
  test "exact match":
    var t = initTable[string, JsonNode]()
    t["keyword"] = %*{"foreground": "#ff0000"}
    let r = t.findTokenSettings("keyword")
    check r != nil
    check r{"foreground"}.getStr == "#ff0000"

  test "exact match takes priority over parent":
    var t = initTable[string, JsonNode]()
    t["keyword"] = %*{"foreground": "#111111"}
    t["keyword.control"] = %*{"foreground": "#222222"}
    let r = t.findTokenSettings("keyword.control")
    check r != nil
    check r{"foreground"}.getStr == "#222222"

  test "parent scope match":
    var t = initTable[string, JsonNode]()
    t["entity"] = %*{"foreground": "#aaaaaa"}
    let r = t.findTokenSettings("entity.name.function")
    check r != nil
    check r{"foreground"}.getStr == "#aaaaaa"

  test "longest parent scope wins":
    var t = initTable[string, JsonNode]()
    t["entity"] = %*{"foreground": "#111111"}
    t["entity.name"] = %*{"foreground": "#222222"}
    let r = t.findTokenSettings("entity.name.function")
    check r != nil
    check r{"foreground"}.getStr == "#222222"

  test "children do not match":
    # A child rule colors only text with that scope, as in TextMate.
    var t = initTable[string, JsonNode]()
    t["entity.name.tag"] = %*{"foreground": "#cc0000"}
    t["variable.language"] = %*{"foreground": "#cc0000"}
    check t.findTokenSettings("entity").isNil
    check t.findTokenSettings("variable").isNil

  test "a rule that sets no color is skipped":
    var t = initTable[string, JsonNode]()
    t["entity"] = %*{"foreground": "#111111"}
    t["entity.name"] = %*{"fontStyle": "bold"}
    check t.findTokenSettings("entity.name.function"){"foreground"}.getStr == "#111111"

  test "no match returns nil":
    var t = initTable[string, JsonNode]()
    t["string"] = %*{"foreground": "#ff0000"}
    let r = t.findTokenSettings("keyword")
    check r == nil

  test "siblings do not match":
    var t = initTable[string, JsonNode]()
    t["keyword.operator"] = %*{"foreground": "#ff0000"}
    let r = t.findTokenSettings("keyword.control")
    check r == nil

  test "theme with keyword.control applies to keyword in makeColorTheme":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "keyword.control", "settings": {"foreground": "#c586c0"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)
    check result[EditorColorPairIndex.keyword].foreground.rgb ==
      Rgb(red: 0xc5, green: 0x86, blue: 0xc0)

  test "a theme coloring only common forms of strings and comments colors them":
    proc rule(scope, fg: string): JsonNode =
      %*{"scope": scope, "settings": {"foreground": fg}}

    let themeJson = %*{
      "colors": {},
      "tokenColors": [
        rule("string.quoted.double", "#000001"),
        rule("string.quoted.single", "#000002"),
        rule("string.regexp", "#000003"),
        rule("comment.line", "#000004"),
        rule("comment.block", "#000005"),
        rule("comment.block.documentation", "#000006"),
      ],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    type I = EditorColorPairIndex
    check result[I.stringLit].foreground.rgb == rgb("#000001")
    check result[I.lspString].foreground.rgb == rgb("#000001")
    check result[I.escapeSequence].foreground.rgb == rgb("#000001")
    check result[I.charLit].foreground.rgb == rgb("#000002")
    check result[I.regexp].foreground.rgb == rgb("#000003")
    check result[I.comment].foreground.rgb == rgb("#000004")
    check result[I.docComment].foreground.rgb == rgb("#000004")
    check result[I.longComment].foreground.rgb == rgb("#000005")
    check result[I.docLongComment].foreground.rgb == rgb("#000006")

  test "a rule for another kind of string does not color strings":
    let themeJson = %*{
      "colors": {"editor.foreground": "#cccccc"},
      "tokenColors": [{"scope": "string.regexp", "settings": {"foreground": "#d16969"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)
    check result[EditorColorPairIndex.stringLit].foreground.rgb == rgb("#cccccc")

  test "theme with entity.name uses parent for entity.name.function lookup":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [{"scope": "entity.name", "settings": {"foreground": "#4ec9b0"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)
    check result[EditorColorPairIndex.functionName].foreground.rgb ==
      Rgb(red: 0x4e, green: 0xc9, blue: 0xb0)
    check result[EditorColorPairIndex.typeName].foreground.rgb ==
      Rgb(red: 0x4e, green: 0xc9, blue: 0xb0)

  test "rules for narrower scopes leave wider text in the editor foreground":
    # Visual Studio Dark colors these scopes only, as VS Code shows.
    let c = makeColorThemeFromVSCodeThemeFile(
      %*{
        "colors": {"editor.foreground": "#d4d4d4"},
        "tokenColors": [
          {
            "scope": [
              "entity.name.tag", "entity.name.function.preprocessor",
              "variable.language",
            ],
            "settings": {"foreground": "#569cd6"},
          },
          {
            "scope": "support.function.git-rebase",
            "settings": {"foreground": "#9cdcfe"},
          },
        ],
      }
    )
    for index in [
      EditorColorPairIndex.functionName, EditorColorPairIndex.function,
      EditorColorPairIndex.`method`, EditorColorPairIndex.typeName,
      EditorColorPairIndex.builtin, EditorColorPairIndex.variable,
    ]:
      checkpoint $index
      check c[index].foreground.rgb == rgb("#d4d4d4")
    # Nim's result and Lua's self are language variables.
    check c[EditorColorPairIndex.specialVar].foreground.rgb == rgb("#569cd6")

  test "a plain variable takes variable.other over variable":
    # Dark 2026: a variable reference is variable.other.readwrite.
    let c = makeColorThemeFromVSCodeThemeFile(
      %*{
        "tokenColors": [
          {"scope": "variable", "settings": {"foreground": "#ffa657"}},
          {"scope": "variable.other", "settings": {"foreground": "#c9d1d9"}},
        ]
      }
    )
    check c[EditorColorPairIndex.variable].foreground.rgb == rgb("#c9d1d9")

  test "links take the Markdown link color":
    let c = makeColorThemeFromVSCodeThemeFile(
      %*{
        "tokenColors": [
          {
            "scope": "markup.underline.link.markdown",
            "settings": {"foreground": "#e6db74"},
          }
        ]
      }
    )
    check c[EditorColorPairIndex.dir].foreground.rgb == rgb("#e6db74")
    check c[EditorColorPairIndex.pcLink].foreground.rgb == rgb("#e6db74")

  test "punctuation takes a punctuation rule, not a narrower one":
    let tagOnly = makeColorThemeFromVSCodeThemeFile(
      %*{
        "colors": {"editor.foreground": "#333333"},
        "tokenColors": [
          {"scope": "punctuation.definition.tag", "settings": {"foreground": "#800000"}}
        ],
      }
    )
    check tagOnly[EditorColorPairIndex.punctuation].foreground.rgb == rgb("#333333")
    let c = makeColorThemeFromVSCodeThemeFile(
      %*{
        "tokenColors": [{"scope": "punctuation", "settings": {"foreground": "#777777"}}]
      }
    )
    check c[EditorColorPairIndex.punctuation].foreground.rgb == rgb("#777777")

suite "vscode_theme - vsCodeSettingsFilePath":
  test "VSCodium settings path":
    let path = vsCodeSettingsFilePath(VsCodeFlavor.VSCodium)
    check path.endsWith("VSCodium/User/settings.json")

  test "CodeOss settings path":
    let path = vsCodeSettingsFilePath(VsCodeFlavor.CodeOss)
    check path.endsWith("Code - OSS/User/settings.json")

  test "VSCode settings path":
    let path = vsCodeSettingsFilePath(VsCodeFlavor.VSCode)
    check path.endsWith("Code/User/settings.json")

suite "vscode_theme - vsCodeUserExtensionsDir":
  test "VSCodium extensions dir":
    let path = vsCodeUserExtensionsDir(VsCodeFlavor.VSCodium)
    check path.endsWith(".vscode-oss/extensions")

  test "CodeOss extensions dir":
    let path = vsCodeUserExtensionsDir(VsCodeFlavor.CodeOss)
    check path.endsWith(".vscode-oss/extensions")

  test "VSCode extensions dir":
    let path = vsCodeUserExtensionsDir(VsCodeFlavor.VSCode)
    check path.endsWith(".vscode/extensions")

when not defined(macosx):
  suite "vscode_theme - vsCodeBuiltinExtensionsDirs":
    test "VSCodium: deb/rpm and AUR installs":
      let dirs = vsCodeBuiltinExtensionsDirs(VsCodeFlavor.VSCodium)
      check "/usr/share/codium/resources/app/extensions" in dirs
      check "/opt/vscodium-bin/resources/app/extensions" in dirs
      check "/usr/share/vscodium/resources/app/extensions" in dirs

    test "CodeOss: Arch install":
      let dirs = vsCodeBuiltinExtensionsDirs(VsCodeFlavor.CodeOss)
      check "/usr/lib/code/extensions" in dirs

    test "VSCode: deb/rpm, AUR and snap installs":
      let dirs = vsCodeBuiltinExtensionsDirs(VsCodeFlavor.VSCode)
      check "/usr/share/code/resources/app/extensions" in dirs
      check "/opt/visual-studio-code/resources/app/extensions" in dirs
      check "/snap/code/current/usr/share/code/resources/app/extensions" in dirs

  suite "vscode_theme - vsCodeUserDataDir":
    test "follows XDG_CONFIG_HOME":
      withTempHome(tmpHome):
        let xdg = tmpHome / "xdg"
        putEnv("XDG_CONFIG_HOME", xdg)
        check vsCodeSettingsFilePath(VsCodeFlavor.VSCode) ==
          xdg / "Code" / "User" / "settings.json"

suite "vscode_theme - loadVSCodeTheme":
  proc writeSettings(flavor: VsCodeFlavor, themeName: string) =
    let path = vsCodeSettingsFilePath(flavor)
    createDir(path.parentDir)
    writeFile(path, $(%*{"workbench.colorTheme": themeName}))

  test "no settings or state file says where it looked":
    withTempHome(tmpHome):
      let r = loadVSCodeTheme()
      require r.isErr
      check r.error.startsWith(
        "no VS Code settings.json or globalStorage/state.vscdb (looked in "
      )
      check vsCodeSettingsFilePath(VsCodeFlavor.VSCode).parentDir in r.error

  test "theme from the user extensions dir":
    withTempHome(tmpHome):
      writeSettings(VsCodeFlavor.VSCode, "My Theme")
      let extDir = tmpHome / ".vscode" / "extensions" / "me.my-theme"
      createDir(extDir / "themes")
      writeFile(
        extDir / "package.json",
        $(
          %*{
            "contributes": {
              "themes":
                [{"label": "My Theme", "uiTheme": "vs-dark", "path": "./themes/t.json"}]
            }
          }
        ),
      )
      writeFile(
        extDir / "themes" / "t.json",
        $(
          %*{
            "colors": {},
            "tokenColors": [{"scope": "keyword", "settings": {"foreground": "#123456"}}],
          }
        ),
      )

      let r = loadVSCodeTheme()
      require r.isOk
      check r.get[EditorColorPairIndex.keyword].foreground.rgb ==
        Rgb(red: 0x12, green: 0x34, blue: 0x56)

  test "a light theme package loads on the light base":
    withTempHome(tmpHome):
      writeSettings(VsCodeFlavor.VSCode, "Pale")
      let extDir = tmpHome / ".vscode" / "extensions" / "me.pale"
      createDir(extDir)
      writeFile(
        extDir / "package.json",
        $(
          %*{
            "contributes":
              {"themes": [{"label": "Pale", "uiTheme": "vs", "path": "./t.json"}]}
          }
        ),
      )
      writeFile(extDir / "t.json", $(%*{"colors": {}}))

      let r = loadVSCodeTheme()
      require r.isOk
      check r.get[EditorColorPairIndex.popupWindow].foreground.rgb == rgb("#333333")
      check r.get[EditorColorPairIndex.popupWindow].background.rgb == rgb("#f3f3f3")

  test "an unreadable theme file says why, not that the theme is missing":
    withTempHome(tmpHome):
      writeSettings(VsCodeFlavor.VSCode, "Broken")
      let extDir = tmpHome / ".vscode" / "extensions" / "me.broken"
      createDir(extDir)
      writeFile(
        extDir / "package.json",
        $(%*{"contributes": {"themes": [{"label": "Broken", "path": "./t.json"}]}}),
      )
      writeFile(extDir / "t.json", """{"colors": {"editor.background" "#000000"}}""")

      let r = loadVSCodeTheme()
      require r.isErr
      check r.error.startsWith("cannot read theme 'Broken': " & extDir / "t.json(")

      removeFile(extDir / "t.json")
      let missing = loadVSCodeTheme()
      require missing.isErr
      check missing.error ==
        "cannot read theme 'Broken': " & extDir / "t.json" & " does not exist"

  test "a theme file with comments and trailing commas loads":
    withTempHome(tmpHome):
      writeSettings(VsCodeFlavor.VSCode, "Jsonc")
      let extDir = tmpHome / ".vscode" / "extensions" / "me.jsonc"
      createDir(extDir)
      writeFile(
        extDir / "package.json",
        $(%*{"contributes": {"themes": [{"label": "Jsonc", "path": "./t.json"}]}}),
      )
      writeFile(
        extDir / "t.json",
        "{\n  // VS Code reads theme files as JSONC\n" &
          "  \"colors\": {\"editor.foreground\": \"#123456\",},\n}",
      )

      let r = loadVSCodeTheme()
      require r.isOk
      check r.get[EditorColorPairIndex.default].foreground.rgb == rgb("#123456")

  test "missing theme names the dirs it searched":
    withTempHome(tmpHome):
      writeSettings(VsCodeFlavor.VSCode, "No Such Theme")
      let extDir = tmpHome / ".vscode" / "extensions"
      createDir(extDir)

      let r = loadVSCodeTheme()
      require r.isErr
      check r.error.startsWith("theme 'No Such Theme' not found (searched ")
      check extDir in r.error

  proc writeThemePackage(dir, label, keyword: string, version = "1.0.0") =
    ## An extension `me.t` at `version` whose theme `label` colors keywords.
    createDir(dir)
    writeFile(
      dir / "package.json",
      $(
        %*{
          "name": "t",
          "publisher": "me",
          "version": version,
          "contributes": {"themes": [{"label": label, "path": "./t.json"}]},
        }
      ),
    )
    writeFile(
      dir / "t.json",
      $(%*{"tokenColors": [{"scope": "keyword", "settings": {"foreground": keyword}}]}),
    )

  proc keywordColor(r: Result[ThemeColors, string]): Rgb =
    r.get[EditorColorPairIndex.keyword].foreground.rgb

  test "an old version VS Code has not deleted yet is not loaded":
    withTempHome(tmpHome):
      writeSettings(VsCodeFlavor.VSCode, "T")
      let extDir = tmpHome / ".vscode" / "extensions"
      writeThemePackage(extDir / "me.t-1.2.0", "T", "#111111", "1.2.0")
      writeThemePackage(extDir / "me.t-1.3.0", "T", "#333333", "1.3.0")
      writeFile(
        extDir / "extensions.json",
        $(
          %*[
            {
              "identifier": {"id": "me.t"},
              "version": "1.3.0",
              "relativeLocation": "me.t-1.3.0",
            }
          ]
        ),
      )

      let r = loadVSCodeTheme()
      require r.isOk
      check r.keywordColor == rgb("#333333")

  test "without extensions.json the newest version of an extension is loaded":
    withTempHome(tmpHome):
      writeSettings(VsCodeFlavor.VSCode, "T")
      let extDir = tmpHome / ".vscode" / "extensions"
      writeThemePackage(extDir / "me.t-1.2.0", "T", "#111111", "1.2.0")
      writeThemePackage(extDir / "me.t-1.3.0", "T", "#333333", "1.3.0")

      let r = loadVSCodeTheme()
      require r.isOk
      check r.keywordColor == rgb("#333333")

  test "the most recently used flavor's theme is loaded":
    withTempHome(tmpHome):
      writeSettings(VsCodeFlavor.VSCodium, "T")
      writeSettings(VsCodeFlavor.VSCode, "T")
      writeThemePackage(tmpHome / ".vscode-oss" / "extensions" / "me.t", "T", "#111111")
      writeThemePackage(tmpHome / ".vscode" / "extensions" / "me.t", "T", "#333333")
      let
        codium = vsCodeSettingsFilePath(VsCodeFlavor.VSCodium)
        code = vsCodeSettingsFilePath(VsCodeFlavor.VSCode)
        now = getTime()

      setLastModificationTime(codium, now - initDuration(days = 30))
      setLastModificationTime(code, now)
      check loadVSCodeTheme().keywordColor == rgb("#333333")

      setLastModificationTime(code, now - initDuration(days = 60))
      check loadVSCodeTheme().keywordColor == rgb("#111111")

  test "a flavor whose settings were never changed has its theme in its state":
    withTempHome(tmpHome):
      let stateDb = vsCodeStateDbPath(VsCodeFlavor.VSCode)
      createDir(stateDb.parentDir)
      writeFile(stateDb, "\x00colorThemeData{\"settingsId\":\"T\"}\x00")
      writeThemePackage(tmpHome / ".vscode" / "extensions" / "me.t", "T", "#333333")

      let r = loadVSCodeTheme()
      require r.isOk
      check r.keywordColor == rgb("#333333")

  test "a settings.json that cannot be parsed says which file":
    withTempHome(tmpHome):
      let settings = vsCodeSettingsFilePath(VsCodeFlavor.VSCode)
      createDir(settings.parentDir)
      writeFile(settings, "{\"workbench.colorTheme\" \"T\"}")

      let r = loadVSCodeTheme()
      require r.isErr
      check r.error.startsWith("cannot read " & settings & ": ")

  test "a blank settings.json is no settings, as in VS Code":
    withTempHome(tmpHome):
      let settings = vsCodeSettingsFilePath(VsCodeFlavor.VSCode)
      createDir(settings.parentDir)
      writeFile(settings, "\n")
      let stateDb = vsCodeStateDbPath(VsCodeFlavor.VSCode)
      createDir(stateDb.parentDir)
      writeFile(stateDb, "\x00colorThemeData{\"settingsId\":\"T\"}\x00")
      writeThemePackage(tmpHome / ".vscode" / "extensions" / "me.t", "T", "#333333")

      let r = loadVSCodeTheme()
      require r.isOk
      check r.keywordColor == rgb("#333333")

  test "the most recently used flavor's failure is reported, not another's theme":
    withTempHome(tmpHome):
      writeSettings(VsCodeFlavor.VSCodium, "T")
      writeSettings(VsCodeFlavor.VSCode, "Gone")
      writeThemePackage(tmpHome / ".vscode-oss" / "extensions" / "me.t", "T", "#111111")
      let now = getTime()
      setLastModificationTime(
        vsCodeSettingsFilePath(VsCodeFlavor.VSCodium), now - initDuration(days = 30)
      )
      setLastModificationTime(vsCodeSettingsFilePath(VsCodeFlavor.VSCode), now)

      let r = loadVSCodeTheme()
      require r.isErr
      check r.error.startsWith("theme 'Gone' not found")

suite "vscode_theme - isNewerVersion":
  test "numbers compare as numbers":
    check "1.10.0".isNewerVersion("1.9.0")
    check not "1.9.0".isNewerVersion("1.10.0")
    check "2.0.0".isNewerVersion("1.99.99")

  test "equal versions are not newer":
    check not "1.2.3".isNewerVersion("1.2.3")
    check not "1.2".isNewerVersion("1.2.0")

  test "a pre-release tag is not compared":
    check "2.0.0-beta".isNewerVersion("1.9.9")
    check not "1.0.0-beta".isNewerVersion("1.0.0")

suite "vscode_theme - vsCodeStateDbPath":
  test "VSCodium state db path":
    let path = vsCodeStateDbPath(VsCodeFlavor.VSCodium)
    check path.endsWith("VSCodium/User/globalStorage/state.vscdb")

  test "CodeOss state db path":
    let path = vsCodeStateDbPath(VsCodeFlavor.CodeOss)
    check path.endsWith("Code - OSS/User/globalStorage/state.vscdb")

  test "VSCode state db path":
    let path = vsCodeStateDbPath(VsCodeFlavor.VSCode)
    check path.endsWith("Code/User/globalStorage/state.vscdb")

suite "vscode_theme - readThemeNameFromStateDb":
  test "reads settingsId from valid data":
    let tmpFile = getTempDir() / "moe_test_statedb_valid"
    defer:
      removeFile(tmpFile)
    let data =
      "somegarbage\x00colorThemeData{\"settingsId\":\"Forest Mist\",\"other\":1}\x00more"
    writeFile(tmpFile, data)
    let result = readThemeNameFromStateDb(tmpFile)
    check result.isSome
    check result.get == "Forest Mist"

  test "returns none when file does not exist":
    let result = readThemeNameFromStateDb("/nonexistent/path/state.vscdb")
    check result.isNone

  test "returns none when colorThemeData pattern not found":
    let tmpFile = getTempDir() / "moe_test_statedb_nopattern"
    defer:
      removeFile(tmpFile)
    writeFile(tmpFile, "productIconThemeData{\"settingsId\":\"Default\"}")
    let result = readThemeNameFromStateDb(tmpFile)
    check result.isNone

  test "returns none when settingsId not found after colorThemeData":
    let tmpFile = getTempDir() / "moe_test_statedb_nosettings"
    defer:
      removeFile(tmpFile)
    writeFile(tmpFile, "colorThemeData{\"otherField\":\"value\"}")
    let result = readThemeNameFromStateDb(tmpFile)
    check result.isNone

  test "returns none for empty file":
    let tmpFile = getTempDir() / "moe_test_statedb_empty"
    defer:
      removeFile(tmpFile)
    writeFile(tmpFile, "")
    let result = readThemeNameFromStateDb(tmpFile)
    check result.isNone

  test "returns none when settingsId value is empty":
    let tmpFile = getTempDir() / "moe_test_statedb_emptyval"
    defer:
      removeFile(tmpFile)
    writeFile(tmpFile, "colorThemeData{\"settingsId\":\"\"}")
    let result = readThemeNameFromStateDb(tmpFile)
    check result.isNone

  test "ignores settingsId from productIconThemeData":
    let tmpFile = getTempDir() / "moe_test_statedb_multi"
    defer:
      removeFile(tmpFile)
    let data =
      "productIconThemeData{\"settingsId\":\"Default\"}\x00colorThemeData{\"settingsId\":\"Monokai\"}"
    writeFile(tmpFile, data)
    let result = readThemeNameFromStateDb(tmpFile)
    check result.isSome
    check result.get == "Monokai"

suite "vscode_theme - resolveThemeIncludes (edge cases)":
  test "returns original when no include field":
    let themeJson = %*{"colors": {"editor.foreground": "#ffffff"}, "tokenColors": []}
    let result = resolveThemeIncludes(themeJson, getTempDir())
    require result.isOk
    check result.get{"colors", "editor.foreground"}.getStr == "#ffffff"

  test "returns original when include is not a string":
    let themeJson = %*{"include": 123, "colors": {}, "tokenColors": []}
    let result = resolveThemeIncludes(themeJson, getTempDir())
    require result.isOk
    check result.get{"include"} != nil

  test "an empty include is no include, as in VS Code":
    let themeJson = %*{"include": "", "colors": {"editor.foreground": "#aaaaaa"}}
    let result = resolveThemeIncludes(themeJson, getTempDir())
    require result.isOk
    check result.get{"colors", "editor.foreground"}.getStr == "#aaaaaa"

  test "a missing include fails the theme, naming the file":
    let themeJson =
      %*{"include": "./nonexistent.json", "colors": {"editor.foreground": "#aaaaaa"}}
    let result = resolveThemeIncludes(themeJson, getTempDir() / "moe_no_such_dir")
    require result.isErr
    check "nonexistent.json" in result.error

  test "multi-level include chain (A -> B -> C)":
    let baseDir = getTempDir() / "moe_test_multi_include"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    let themeC = %*{
      "colors": {"editor.background": "#111111"},
      "tokenColors": [{"scope": "comment", "settings": {"foreground": "#666666"}}],
    }
    writeFile(baseDir / "c.json", $themeC)

    let themeB = %*{
      "include": "./c.json",
      "colors": {"editor.foreground": "#bbbbbb"},
      "tokenColors": [],
    }
    writeFile(baseDir / "b.json", $themeB)

    let themeA = %*{
      "include": "./b.json",
      "colors": {"editor.foreground": "#aaaaaa"},
      "tokenColors": [{"scope": "keyword", "settings": {"foreground": "#ff0000"}}],
    }

    let resolved = resolveThemeIncludes(themeA, baseDir)
    require resolved.isOk
    check resolved.get{"colors", "editor.foreground"}.getStr == "#aaaaaa"
    check resolved.get{"colors", "editor.background"}.getStr == "#111111"
    check resolved.get{"tokenColors"}.len == 2

  test "base theme with missing colors key":
    let baseDir = getTempDir() / "moe_test_include_nocol"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    let baseTheme =
      %*{"tokenColors": [{"scope": "keyword", "settings": {"foreground": "#ff0000"}}]}
    writeFile(baseDir / "base.json", $baseTheme)

    let childTheme = %*{
      "include": "./base.json",
      "colors": {"editor.foreground": "#cccccc"},
      "tokenColors": [],
    }

    let resolved = resolveThemeIncludes(childTheme, baseDir)
    require resolved.isOk
    check resolved.get{"colors", "editor.foreground"}.getStr == "#cccccc"
    check resolved.get{"tokenColors"}.len == 1

  test "base theme with missing tokenColors key":
    let baseDir = getTempDir() / "moe_test_include_notok"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    let baseTheme = %*{"colors": {"editor.background": "#222222"}}
    writeFile(baseDir / "base.json", $baseTheme)

    let childTheme = %*{
      "include": "./base.json",
      "colors": {},
      "tokenColors": [{"scope": "string", "settings": {"foreground": "#00ff00"}}],
    }

    let resolved = resolveThemeIncludes(childTheme, baseDir)
    require resolved.isOk
    check resolved.get{"colors", "editor.background"}.getStr == "#222222"
    check resolved.get{"tokenColors"}.len == 1

  test "an include with invalid JSON fails the theme, naming the file":
    let baseDir = getTempDir() / "moe_test_include_invalid"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    writeFile(baseDir / "bad.json", "not valid json{{{")

    let childTheme = %*{
      "include": "./bad.json",
      "colors": {"editor.foreground": "#dddddd"},
      "tokenColors": [],
    }

    let resolved = resolveThemeIncludes(childTheme, baseDir)
    require resolved.isErr
    check "bad.json" in resolved.error

  test "a theme that includes itself fails instead of looping":
    let baseDir = getTempDir() / "moe_test_include_self"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    writeFile(
      baseDir / "a.json",
      $(%*{"include": "./a.json", "colors": {"editor.foreground": "#aaaaaa"}}),
    )
    let packageJson =
      %*{"contributes": {"themes": [{"label": "A", "path": "./a.json"}]}}
    let result =
      parseVsCodeThemeJson(packageJson.themeEntry("A"), baseDir / "package.json")
    require result.isErr
    check "include cycle" in result.error

  test "an include cycle fails the theme":
    let baseDir = getTempDir() / "moe_test_include_cycle"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    writeFile(
      baseDir / "a.json",
      $(%*{"include": "./b.json", "colors": {"editor.foreground": "#aaaaaa"}}),
    )
    writeFile(
      baseDir / "b.json",
      $(
        %*{
          "include": "./a.json",
          "colors": {"editor.foreground": "#bbbbbb", "editor.background": "#111111"},
        }
      ),
    )
    let packageJson =
      %*{"contributes": {"themes": [{"label": "A", "path": "./a.json"}]}}
    let result =
      parseVsCodeThemeJson(packageJson.themeEntry("A"), baseDir / "package.json")
    require result.isErr
    check "include cycle" in result.error

  test "an include cycle through a symlink fails instead of looping":
    let baseDir = getTempDir() / "moe_test_include_symlink"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    writeFile(
      baseDir / "a.json",
      $(%*{"include": "./link.json", "colors": {"editor.foreground": "#aaaaaa"}}),
    )
    createSymlink(baseDir / "a.json", baseDir / "link.json")
    let packageJson =
      %*{"contributes": {"themes": [{"label": "A", "path": "./a.json"}]}}
    let result =
      parseVsCodeThemeJson(packageJson.themeEntry("A"), baseDir / "package.json")
    require result.isErr
    check "include cycle" in result.error

suite "vscode_theme - parseVsCodeThemeJson":
  test "loads theme file matching by label":
    let baseDir = getTempDir() / "moe_test_parsetheme"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    let themeContent = %*{"colors": {"editor.foreground": "#abcdef"}, "tokenColors": []}
    writeFile(baseDir / "my_theme.json", $themeContent)

    let packageJson =
      %*{"contributes": {"themes": [{"label": "My Theme", "path": "./my_theme.json"}]}}
    let result =
      parseVsCodeThemeJson(packageJson.themeEntry("My Theme"), baseDir / "package.json")
    require result.isOk
    check result.get{"colors", "editor.foreground"}.getStr == "#abcdef"

  test "error names a theme file that does not exist":
    let baseDir = getTempDir() / "moe_test_parsetheme_nofile"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    let packageJson = %*{
      "contributes": {"themes": [{"label": "My Theme", "path": "./nonexistent.json"}]}
    }
    let result =
      parseVsCodeThemeJson(packageJson.themeEntry("My Theme"), baseDir / "package.json")
    require result.isErr
    check result.error == baseDir / "nonexistent.json" & " does not exist"

  test "error when path field is missing":
    let packageJson = %*{"contributes": {"themes": [{"label": "My Theme"}]}}
    let result =
      parseVsCodeThemeJson(packageJson.themeEntry("My Theme"), "/tmp/package.json")
    require result.isErr
    check result.error == "/tmp/package.json gives the theme no path"

  test "resolves include chain in loaded theme":
    let baseDir = getTempDir() / "moe_test_parsetheme_include"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    let baseTheme = %*{
      "colors": {"editor.background": "#000000"},
      "tokenColors": [{"scope": "comment", "settings": {"foreground": "#999999"}}],
    }
    writeFile(baseDir / "base.json", $baseTheme)

    let childTheme = %*{
      "include": "./base.json",
      "colors": {"editor.foreground": "#ffffff"},
      "tokenColors": [],
    }
    writeFile(baseDir / "child.json", $childTheme)

    let packageJson =
      %*{"contributes": {"themes": [{"label": "Child Theme", "path": "./child.json"}]}}
    let result = parseVsCodeThemeJson(
      packageJson.themeEntry("Child Theme"), baseDir / "package.json"
    )
    require result.isOk
    check result.get{"colors", "editor.foreground"}.getStr == "#ffffff"
    check result.get{"colors", "editor.background"}.getStr == "#000000"
    check result.get{"tokenColors"}.len == 1

suite "vscode_theme - editor.background propagation":
  test "applies to all elements with default background":
    let themeJson = %*{"colors": {"editor.background": "#2d3142"}, "tokenColors": []}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)
    let expectedBg = Rgb(red: 0x2d, green: 0x31, blue: 0x42)

    check result[EditorColorPairIndex.default].background.rgb == expectedBg
    check result[EditorColorPairIndex.keyword].background.rgb == expectedBg
    check result[EditorColorPairIndex.operator].background.rgb == expectedBg
    check result[EditorColorPairIndex.whitespace].background.rgb == expectedBg
    check result[EditorColorPairIndex.function].background.rgb == expectedBg
    check result[EditorColorPairIndex.`method`].background.rgb == expectedBg
    check result[EditorColorPairIndex.namespace].background.rgb == expectedBg
    check result[EditorColorPairIndex.className].background.rgb == expectedBg
    check result[EditorColorPairIndex.decorator].background.rgb == expectedBg
    check result[EditorColorPairIndex.parameter].background.rgb == expectedBg
    check result[EditorColorPairIndex.property].background.rgb == expectedBg
    check result[EditorColorPairIndex.enumName].background.rgb == expectedBg
    check result[EditorColorPairIndex.enumMember].background.rgb == expectedBg

  test "preserves non-default backgrounds":
    let themeJson = %*{"colors": {"editor.background": "#2d3142"}, "tokenColors": []}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)
    let themeBg = Rgb(red: 0x2d, green: 0x31, blue: 0x42)

    # Status line has non-black default (#61afef) - should NOT be changed
    check result[EditorColorPairIndex.statusLineNormalMode].background.rgb != themeBg
    # Select area has non-black default (#5c3d6e) - should NOT be changed
    check result[EditorColorPairIndex.selectArea].background.rgb != themeBg
    # Search result has non-black default (#be5046) - should NOT be changed
    check result[EditorColorPairIndex.searchResult].background.rgb != themeBg
    # Current line bg has non-black default (#3e4452) - should NOT be changed
    check result[EditorColorPairIndex.currentLineBg].background.rgb != themeBg

suite "vscode_theme - VS Code's defaults by theme kind":
  let empty = %*{"colors": {}, "tokenColors": []}

  test "a light theme gets VS Code's light colors, readable popups included":
    let c = makeColorThemeFromVSCodeThemeFile(empty, vtkLight)

    check c[EditorColorPairIndex.default].foreground.rgb == rgb("#333333")
    check c[EditorColorPairIndex.default].background.rgb == rgb("#ffffff")
    check c[EditorColorPairIndex.statusLineNormalMode].background.rgb == rgb("#007acc")
    check c[EditorColorPairIndex.popupWindow].foreground.rgb == rgb("#333333")
    check c[EditorColorPairIndex.popupWindow].background.rgb == rgb("#f3f3f3")
    check c[EditorColorPairIndex.popupWinCurrentLine].foreground.rgb == rgb("#ffffff")
    check c[EditorColorPairIndex.popupWinCurrentLine].background.rgb == rgb("#0060c0")
    check c[EditorColorPairIndex.lineNum].foreground.rgb == rgb("#237893")
    check c[EditorColorPairIndex.lineNum].background.rgb == rgb("#ffffff")
    check c[EditorColorPairIndex.currentLineNum].foreground.rgb == rgb("#0b216f")
    check c[EditorColorPairIndex.currentLineNum].background.rgb == rgb("#ffffff")
    check c[EditorColorPairIndex.currentLineBg].background.rgb == rgb("#eeeeee")

  test "high contrast light keeps the cursor line light":
    # VS Code draws only a border there, so moe's light theme fills it.
    let c = makeColorThemeFromVSCodeThemeFile(empty, vtkHcLight)
    for index in [
      EditorColorPairIndex.currentLineBg, EditorColorPairIndex.currentColumnBg
    ]:
      check c[index].background.rgb == rgb("#eeeeee")

  test "what VS Code has no color for comes from moe's light theme":
    let c = makeColorThemeFromVSCodeThemeFile(empty, vtkLight)
    check c[EditorColorPairIndex.filerDirectory].foreground ==
      LightColors[EditorColorPairIndex.filerDirectory].foreground
    check c[EditorColorPairIndex.configModePopupBg].background ==
      LightColors[EditorColorPairIndex.configModePopupBg].background

  test "moe's own colors follow the editor background, not the declared kind":
    # No uiTheme means dark, yet the theme paints a light editor.
    let light = makeColorThemeFromVSCodeThemeFile(
      %*{"colors": {"editor.background": "#fafafa"}}, vtkDark
    )
    check light[EditorColorPairIndex.filerDirectory].foreground ==
      LightColors[EditorColorPairIndex.filerDirectory].foreground
    check light[EditorColorPairIndex.diffViewerAddedLineBg] ==
      LightColors[EditorColorPairIndex.diffViewerAddedLineBg]

    let dark = makeColorThemeFromVSCodeThemeFile(
      %*{"colors": {"editor.background": "#202020"}}, vtkLight
    )
    check dark[EditorColorPairIndex.filerDirectory].foreground ==
      DefaultColors[EditorColorPairIndex.filerDirectory].foreground
    # VS Code's defaults still follow the kind.
    check dark[EditorColorPairIndex.popupWindow].background.rgb == rgb("#f3f3f3")

  test "a default that refers to another color follows the theme's value":
    let c = makeColorThemeFromVSCodeThemeFile(
      %*{"colors": {"editor.foreground": "#123456", "editor.background": "#fafafa"}},
      vtkLight,
    )
    # editorSuggestWidget.foreground -> editor.foreground
    check c[EditorColorPairIndex.popupWindow].foreground.rgb == rgb("#123456")
    # tab.activeBackground and the gutter -> editor.background
    check c[EditorColorPairIndex.currentTab].background.rgb == rgb("#fafafa")
    check c[EditorColorPairIndex.lineNum].background.rgb == rgb("#fafafa")

  test "a translucent default is blended onto the background it is drawn on":
    # tab.inactiveForeground is tab.activeForeground at 70% in light themes,
    # drawn on tab.inactiveBackground (#ececec).
    let c = makeColorThemeFromVSCodeThemeFile(
      %*{"colors": {"tab.activeForeground": "#000000"}}, vtkLight
    )
    check c[EditorColorPairIndex.tab].foreground.rgb == rgb("#474747")
    # Dark: #ffffff at 50% on #2d2d2d, not on the editor's #1e1e1e.
    let dark = makeColorThemeFromVSCodeThemeFile(empty)
    check dark[EditorColorPairIndex.tab].foreground.rgb == rgb("#969696")

  test "merge decorations keep the editor foreground":
    let c = makeColorThemeFromVSCodeThemeFile(empty, vtkLight)
    check c[EditorColorPairIndex.gitConflictMarker].foreground.rgb == rgb("#333333")
    check c[EditorColorPairIndex.gitConflictMarker].background.rgb == rgb("#9fe3d6")

  test "every pair is readable":
    for kind in VsThemeKind:
      checkpoint $kind
      check makeColorThemeFromVSCodeThemeFile(empty, kind).unreadablePairs ==
        newSeq[string]()

  test "with no status bar background, the editor's shows through":
    let c = makeColorThemeFromVSCodeThemeFile(empty, vtkHcDark)
    for index in [
      EditorColorPairIndex.statusLineNormalMode,
      EditorColorPairIndex.statusLineNormalModeLabel,
      EditorColorPairIndex.statusLineNormalModeInactive,
    ]:
      check c[index].foreground.rgb == rgb("#ffffff")
      check c[index].background.rgb == rgb("#000000")
    check c[EditorColorPairIndex.tab].background.rgb == rgb("#000000")

  test "high contrast gives selected text its own color":
    let dark = makeColorThemeFromVSCodeThemeFile(empty, vtkHcDark)
    check dark[EditorColorPairIndex.selectArea].foreground.rgb == rgb("#000000")
    check dark[EditorColorPairIndex.selectArea].background.rgb == rgb("#f3f518")
    let light = makeColorThemeFromVSCodeThemeFile(empty, vtkHcLight)
    check light[EditorColorPairIndex.selectArea].foreground.rgb == rgb("#ffffff")
    check light[EditorColorPairIndex.selectArea].background.rgb == rgb("#0f4a85")

  test "where VS Code draws only a border, moe's highlight stays whole":
    let c = makeColorThemeFromVSCodeThemeFile(empty, vtkHcDark)
    for index in [
      EditorColorPairIndex.searchResult, EditorColorPairIndex.gitConflictOurs,
      EditorColorPairIndex.backupManagerCurrentLine, EditorColorPairIndex.replaceText,
    ]:
      check c[index] == DefaultColors[index]

  test "replacement text is VS Code's inserted text":
    let c = makeColorThemeFromVSCodeThemeFile(empty)
    check c[EditorColorPairIndex.replaceText].foreground.rgb == rgb("#bbbbbb")
    # #9ccc2c at 0.2 over #1e1e1e
    check c[EditorColorPairIndex.replaceText].background.rgb == rgb("#374121")

  test "high contrast inverts the selected suggestion":
    let c = makeColorThemeFromVSCodeThemeFile(empty, vtkHcLight)
    check c[EditorColorPairIndex.popupWinCurrentLine].foreground.rgb == rgb("#ffffff")
    check c[EditorColorPairIndex.popupWinCurrentLine].background.rgb == rgb("#292929")

  test "a token rule with only a font style keeps the editor foreground":
    let c = makeColorThemeFromVSCodeThemeFile(
      %*{
        "colors": {"editor.foreground": "#123456"},
        "tokenColors": [{"scope": "keyword", "settings": {"fontStyle": "italic"}}],
      }
    )
    check c[EditorColorPairIndex.keyword].foreground.rgb == rgb("#123456")

  test "text without a token rule is the editor foreground, as in VS Code":
    let c = makeColorThemeFromVSCodeThemeFile(
      %*{"colors": {"editor.foreground": "#123456"}}, vtkLight
    )
    for index in [
      EditorColorPairIndex.parameter, EditorColorPairIndex.punctuation,
      EditorColorPairIndex.functionName, EditorColorPairIndex.comment,
    ]:
      checkpoint $index
      check c[index].foreground.rgb == rgb("#123456")
    # Not token text: VS Code's own color, and moe's log viewer colors.
    check c[EditorColorPairIndex.whitespace].foreground.rgb != rgb("#123456")
    check c[EditorColorPairIndex.logError].foreground ==
      LightColors[EditorColorPairIndex.logError].foreground

suite "vscode_theme - themeKind":
  proc entry(uiTheme: JsonNode): JsonNode =
    result = %*{"label": "T", "path": "./t.json"}
    if uiTheme != nil:
      result["uiTheme"] = uiTheme

  test "uiTheme names the kind":
    check entry(%"vs").themeKind == vtkLight
    check entry(%"vs-dark").themeKind == vtkDark
    check entry(%"hc-black").themeKind == vtkHcDark
    check entry(%"hc-light").themeKind == vtkHcLight

  test "missing or unknown uiTheme is dark, as in VS Code":
    check entry(nil).themeKind == vtkDark
    check entry(%"neon").themeKind == vtkDark

suite "vscode_theme - TextMate themes":
  const TmTheme = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>name</key>
  <string>Sample &amp; Co</string>
  <key>settings</key>
  <array>
    <dict>
      <key>settings</key>
      <dict>
        <key>background</key>
        <string>#272822</string>
        <key>foreground</key>
        <string>#F8F8F2</string>
        <key>caret</key>
        <string>#F8F8F0</string>
      </dict>
    </dict>
    <dict>
      <key>name</key>
      <string>Keyword</string>
      <key>scope</key>
      <string>keyword, storage</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>#F92672</string>
        <key>background</key>
        <string>#000000</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
"""

  template withThemeDir(name: string, body: untyped) =
    let dir {.inject.} = getTempDir() / name
    createDir(dir)
    defer:
      removeDir(dir)
    body

  test "an empty tokenColors string is ignored, as in VS Code":
    withThemeDir "moe_test_tmtheme_empty":
      writeFile(
        dir / "t.json",
        $(%*{"colors": {"editor.background": "#111111"}, "tokenColors": ""}),
      )
      let theme = readThemeFile(dir / "t.json")
      require theme.isOk
      let c = makeColorThemeFromVSCodeThemeFile(theme.get)
      check c[EditorColorPairIndex.default].background.rgb == rgb("#111111")

  test "tokenColors naming a TextMate theme takes its rules and editor colors":
    withThemeDir "moe_test_tmtheme_tokencolors":
      writeFile(dir / "syntax.tmTheme", TmTheme)
      writeFile(
        dir / "t.json",
        $(
          %*{
            "colors":
              {"editor.background": "#111111", "editor.selectionBackground": "#49483e"},
            "tokenColors": "./syntax.tmTheme",
          }
        ),
      )
      let theme = readThemeFile(dir / "t.json")
      require theme.isOk
      let c = makeColorThemeFromVSCodeThemeFile(theme.get)
      check c[EditorColorPairIndex.keyword].foreground.rgb == rgb("#f92672")
      check c[EditorColorPairIndex.default].foreground.rgb == rgb("#f8f8f2")
      # The TextMate theme's global settings win, as in VS Code.
      check c[EditorColorPairIndex.default].background.rgb == rgb("#272822")
      # Colors the TextMate theme leaves alone stay the file's.
      check c[EditorColorPairIndex.selectArea].background.rgb == rgb("#49483e")

  test "a missing or unparsable TextMate theme is an error naming it":
    withThemeDir "moe_test_tmtheme_missing":
      writeFile(dir / "t.json", $(%*{"tokenColors": "./syntax.tmTheme"}))
      let missing = readThemeFile(dir / "t.json")
      require missing.isErr
      check missing.error == dir / "syntax.tmTheme" & " does not exist"

      writeFile(dir / "syntax.tmTheme", "<plist><dict>")
      let broken = readThemeFile(dir / "t.json")
      require broken.isErr
      check broken.error.startsWith("cannot read " & dir / "syntax.tmTheme" & ": ")

      writeFile(dir / "syntax.tmTheme", "<plist><dict></dict></plist>")
      let empty = readThemeFile(dir / "t.json")
      require empty.isErr
      check empty.error == dir / "syntax.tmTheme" & " has no settings array"

  test "a package's theme file may itself be a TextMate theme":
    withThemeDir "moe_test_tmtheme_path":
      writeFile(dir / "t.tmTheme", TmTheme)
      let packageJson =
        %*{"contributes": {"themes": [{"label": "T", "path": "./t.tmTheme"}]}}
      let theme =
        parseVsCodeThemeJson(packageJson.themeEntry("T"), dir / "package.json")
      require theme.isOk
      let c = makeColorThemeFromVSCodeThemeFile(theme.get)
      check c[EditorColorPairIndex.keyword].foreground.rgb == rgb("#f92672")
      check c[EditorColorPairIndex.default].background.rgb == rgb("#272822")

  test "the old JSON format of TextMate rules loads, keeping its include":
    withThemeDir "moe_test_tmtheme_json_settings":
      writeFile(
        dir / "base.json", $(%*{"colors": {"editor.selectionBackground": "#49483e"}})
      )
      writeFile(
        dir / "t.json",
        $(
          %*{
            "include": "./base.json",
            "settings": [
              {"settings": {"background": "#272822"}},
              {"scope": "comment", "settings": {"foreground": "#75715e"}},
            ],
          }
        ),
      )
      let packageJson =
        %*{"contributes": {"themes": [{"label": "T", "path": "./t.json"}]}}
      let theme =
        parseVsCodeThemeJson(packageJson.themeEntry("T"), dir / "package.json")
      require theme.isOk
      let c = makeColorThemeFromVSCodeThemeFile(theme.get)
      check c[EditorColorPairIndex.comment].foreground.rgb == rgb("#75715e")
      check c[EditorColorPairIndex.default].background.rgb == rgb("#272822")
      check c[EditorColorPairIndex.selectArea].background.rgb == rgb("#49483e")

  test "an included theme may take its rules from a TextMate theme":
    withThemeDir "moe_test_tmtheme_include":
      writeFile(dir / "syntax.tmTheme", TmTheme)
      writeFile(dir / "base.json", $(%*{"tokenColors": "./syntax.tmTheme"}))
      let child = %*{
        "include": "./base.json",
        "tokenColors": [{"scope": "comment", "settings": {"foreground": "#75715e"}}],
      }
      let resolved = resolveThemeIncludes(child, dir)
      require resolved.isOk
      let c = makeColorThemeFromVSCodeThemeFile(resolved.get)
      check c[EditorColorPairIndex.keyword].foreground.rgb == rgb("#f92672")
      check c[EditorColorPairIndex.comment].foreground.rgb == rgb("#75715e")
