
template tryIgnore*(body: untyped) =
  try:
    body
  except:
    discard

template tryBool*(body: untyped): bool =
  try:
    body
    return true
  except:
    return false

template tryLog*(body: untyped) =
  try:
    body
  except:
    let inf = instantiationInfo()
    log(muk, getCurrentExceptionMsg() & "\n" & $inf)