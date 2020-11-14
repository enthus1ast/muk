const CHUNK_SIZE* = 4096 * 8
type
  Chunk* = string
  UploadInfo* = object
    name*: string
    size*: int