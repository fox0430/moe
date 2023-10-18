switch("path", "$projectDir/../src")

switch("d", "unitTest")

when (NimMajor, NimMinor, NimPatch) == (1, 6, 12):
  switch("warning", "BareExcept:off")
