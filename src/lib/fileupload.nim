import asyncfile, asyncdispatch, os
import ../types/tuploadInfo

const
  CHUNK_SIZE* = 4096 * 8

proc getUploadInfo*(fh: AsyncFile, path: string): UploadInfo =
  result = UploadInfo()
  result.size = fh.getFileSize().int
  result.name = path.extractFilename()
