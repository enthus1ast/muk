type
  PlaylistSongs* = seq[PlaylistSong]
  PlaylistSong* = object
    filename*: string
    current*: bool
    id*: int
