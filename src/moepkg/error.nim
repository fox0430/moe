type Error = object of Exception

proc InvalidItemError*(message: string) =
  raise newException(Error, message)
