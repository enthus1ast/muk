import strutils

# proc tokenize(line: string): seq[string] =
#   for ch in line:
#     ch.

proc filter*(query: string, elems: seq[string]): seq[int] =
  if query.len <= 2: return @[]
  let queryClean = query.toLower()
  for idx, elem in elems:
    let elemClean = elem.toLower().strip()
    if elemClean.contains(queryClean): result.add idx