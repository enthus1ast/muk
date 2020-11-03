import os
when defined(windows):
  const mpvDllFrom = "windows/mpv-1.dll"
  const mpvDllTo = "mpv-1.dll"
  echo "================================================"
  echo "| Building mukd for windows"
  echo "================================================"
  switch("passl", "-L " & thisDir() / "windows/")
  switch("passl", "-lmpv")
  if not fileExists(mpvDllTo):
    echo "copy dll: ", mpvDllFrom, " -> ", mpvDllTo
    cpFile(mpvDllFrom, mpvDllTo) # copy the dll next to the binary

elif defined(linux):
  echo "================================================"
  echo "| Building mukd for linux"
  echo "================================================"
  switch("passl", "-L " & thisDir() / "linux/")
  switch("passl", "-lmpv")
