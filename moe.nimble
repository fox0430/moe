# Package

version       = "0.1.7"
author        = "fox0430"
description   = "A command lined based text editor"
license       = "GPLv3"
srcDir        = "src"
bin           = @["moe"]

# Dependencies

requires "nim >= 1.0"
requires "https://github.com/walkre-niboshi/nim-ncurses >= 1.0.1"
requires "unicodedb >= 0.8.0"
requires "parsetoml >= 0.4.0"
