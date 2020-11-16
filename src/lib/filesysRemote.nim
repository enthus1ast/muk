from filesys import ActionKind, Action
import asyncdispatch
import ../mukc
import ../types/tmessages

type
  FilesystemRemote* = ref object
    currentPath*: string
    mukc*: Mukc

proc newFilesystemRemote*(mukc: Mukc): FilesystemRemote =
  result = FilesystemRemote()
  result.mukc = mukc

proc up*(fs: FilesystemRemote) =
  ## One folder up
  # fs.currentPath = (fs.currentPath / "..").absolutePath()
  let answ = waitFor fs.mukc.remoteFsUp()
  fs.currentPath = answ.currentPath

proc ls*(fs: FilesystemRemote): seq[string] =
  let answ = waitFor fs.mukc.remoteFsLs()
  fs.currentPath = answ.currentPath
  return answ.listing

proc action*(fs: FilesystemRemote, path: string): Action =
  let answ = waitFor fs.mukc.remoteFsAction(path)
  case answ.kind
  of ActionKind.File:
    discard
  of ActionKind.Folder:
    fs.currentPath = answ.folderPath
  of ActionKind.None:
    discard
  return answ