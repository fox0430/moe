import unittest
import moepkg/[unicodeext]
include moepkg/historymanager

suite "History Manager":
  test"Gnerate file name patern":
    echo generateFilenamePatern(ru"test.nim")
