type
  SongInfo* = object ## Normalized song information (mpv gives json)
    album*: string
    artist*: string
    title*: string
    path*: string