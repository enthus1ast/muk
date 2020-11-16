# TODO something for os?

proc expandEnv(path: string): string =
  ## Expands the environment variables in a path
  ## Windows:
  ##  "C:/%foo%/baa
  ## Posix bash:
  ##  C:/$foo/baa
  discard

when isMainModule:
  import unittest
  import os

  suite "expandEnv":
    setup():
      putEnv("foo", "baa")
    when defined(windows):
      test("windows"):
        assert expandEnv("C:/%foo%/baa") == "C:/baa/baa"
