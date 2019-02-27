# Package

version       = "0.0.4"
author        = "fox0430/walkre"
description   = "a command lined based text editor"
license       = "GPLv3"
srcDir        = "src"
bin           = @["moe"]

# Dependencies

requires "nim >= 0.19.0"
requires "https://github.com/walkre-niboshi/nim-ncurses >= 0.1.0"
requires "unicodedb >= 0.5.2"
requires "parsetoml >= 0.4.0"
