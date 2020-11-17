import asyncfile, asyncdispatch, os, strutils
import ../types/tuploadInfo

const
  CHUNK_SIZE* = 4096 * 8

proc getUploadInfo*(fh: AsyncFile, path: string): UploadInfo =
  result = UploadInfo()
  result.size = fh.getFileSize().int
  result.name = path.extractFilename()

iterator chunkFile*(fh: AsyncFile): Chunk =
  var buffer = newStringOfCap(CHUNK_SIZE)
  while true:
    buffer = waitFor fh.read(CHUNK_SIZE)
    if buffer == "": break
    yield buffer


when isMainModule:
  let path = """C:\Users\david\Music\2004 - Utopia City\03 - Yesterday Is Today.mp3"""
  var fh = openAsync(path, fmRead)
  let uploadInfo = getUploadInfo(fh, path)

  var progress = 0
  for chunk in chunkFile(fh):
    # echo chunk
    progress.inc chunk.len
    stdout.write progress.formatSize().alignLeft(10) & "/" & uploadInfo.size.formatSize().align(10) & "\r"
    stdout.flushFile()
    # sleep(5)