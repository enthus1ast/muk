type
  MukdStatus* = object
    ## This is used to periodically store the
    ## Status to the filesystem, to load it on mukd restart
    currentSongIdx*: int
    pause*: bool
    timPos*: float
