# Package

version       = "0.0.81"
author        = "fox0430"
description   = "A command lined based text editor"
license       = "GPLv3"
srcDir        = "src"
bin           = @["moe"]

# Dependencies

requires "nim >= 0.19.6"
requires "https://github.com/walkre-niboshi/nim-ncurses >= 0.1.0"
requires "unicodedb >= 0.7.0"
requires "parsetoml >= 0.4.0"
