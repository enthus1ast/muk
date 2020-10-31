import os
type
  ActionKind* {.pure.} = enum
    File, Folder, None
  Action* = object
    case kind*: ActionKind
    of ActionKind.File:
      filePath*: string
      fileName*: string
    of ActionKind.Folder:
      folderPath*: string
      folderContent*: seq[string]
    of ActionKind.None:
      why*: string

  Filesystem = ref object
    currentPath*: string
    supportedExt: seq[string]

proc newFilesystem*(currentPath = getAppDir(), supportedExt = @[".mp3", ".mp4", ".webm"]): Filesystem =
  result = Filesystem()
  result.currentPath = currentPath.absolutePath()
  result.supportedExt = supportedExt

proc up*(fs: Filesystem) =
  ## One folder up
  fs.currentPath = (fs.currentPath / "..").absolutePath()

proc down*(fs: Filesystem, folder: string) =
  let newPath = (fs.currentPath / folder.lastPathPart()).absolutePath()
  if dirExists(newPath):
    fs.currentPath = newPath

proc ls*(fs: Filesystem): seq[string] =
  result.add ".."
  for (kind, path) in walkDir(fs.currentPath):
    var line: string # = path
    if kind == pcDir or kind == pcLinkToDir:
      line = path.lastPathPart() # & "/"
      result.add line
    elif kind == pcFile or kind == pcLinkToFile:
      line = path.lastPathPart()
      # echo line ,  line.splitFile().ext, fs.supportedExt
      # quit()
      if fs.supportedExt.contains(line.splitFile().ext):
        result.add line

proc action*(fs: Filesystem, path: string): Action =
  let actionPath = (fs.currentPath / path).absolutePath()
  # echo path
  var kind: ActionKind
  if path.lastPathPart() == "..":
    result = Action(kind: ActionKind.Folder)
    fs.up()
    result.folderContent = fs.ls()
  elif dirExists(actionPath):
    result = Action(kind: ActionKind.Folder)
    fs.down(actionPath)
    result.folderPath = actionPath
    result.folderContent = fs.ls()
  elif fileExists(actionPath):
    result = Action(kind: ActionKind.File)
    result.filePath = actionPath
    result.fileName = result.filePath.extractFilename()
  else:
    result = Action(kind: ActionKind.None)
    result.why = "path not found"

when isMainModule:
  var fs = newFilesystem()
  echo fs.action("config.nims")
  echo fs.currentPath
  fs.up
  echo fs.currentPath
  echo fs.action("config.nims")
  echo fs.ls
