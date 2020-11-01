from ../../search import filter

doAssert filter("fo", @["faa", "foo", "baz"]) == @[]
doAssert filter("foo", @["faa", "foo", "baz"]) == @[1]

doAssert filter("foo", @["faa", "faafoo", "baz"]) == @[1]
doAssert filter("foo", @["faa", "faafooo", "baz"]) == @[1]
doAssert filter("foo", @["faafoo", "faafooo", "baz"]) == @[0,1]


doAssert filter("foo", @["faa", "fOo", "baz"]) == @[1]