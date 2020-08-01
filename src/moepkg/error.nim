type Error = object of Exception

proc exception*(message: string) =
  raise newException(Error, message)
