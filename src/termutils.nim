###### Patches for  illwill or std/terminal.nim ?? ##########################
proc SetConsoleTitleA*(lpConsoleTitle: cstring): bool {.importc, dynlib: "kernel32.dll".}
proc setTerminalTitle*(title: string) =
  if title != "" :
    when defined(posix):
      const CSIstart = 0x1b.chr & "]" & "0" & ";"
      const CSIend   = 0x07.chr
      stdout.write(CSIstart & title & CSIend)
      stdout.flushFile()
    when defined(windows):
      discard SetConsoleTitleA(title)
#####################################################