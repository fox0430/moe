switch("d", "unitTest")
switch("d", "nimOldCaseObjects")

when (NimMajor, NimMinor, NimPatch) >= (1, 6, 12):
  switch("warning", "BareExcept:off")
