# Package

version       = "0.0.8"
author        = "fox0430"
description   = "A command lined based text editor"
license       = "GPLv3"
srcDir        = "src"
bin           = @["moe"]

# Dependencies

requires "nim >= 0.19.6"
requires "https://github.com/walkre-niboshi/nim-ncurses >= 0.1.0"
requires "unicodedb >= 0.6.0"
requires "parsetoml >= 0.4.0"
