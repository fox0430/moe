# Package

version       = "0.1.2"
author        = "fox0430"
description   = "A command lined based text editor"
license       = "GPLv3"
srcDir        = "src"
bin           = @["moe"]

# Dependencies

requires "nim >= 0.20.0"
requires "https://github.com/walkre-niboshi/nim-ncurses >= 1.0.1"
requires "unicodedb >= 0.7.2"
requires "parsetoml >= 0.4.0"
