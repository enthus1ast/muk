type
  MukEvent* = enum
    MukUnknown
    MukPauseToggle,
    MukSeekForward
    MukSeekBackward
    MukSeekForwardFast
    MukSeekBackwardFast
    MukSwitchPane
    MukDebugInfo
    MukPrevFromPlaylist
    MukNextFromPlaylist
    MukClearPlaylist

    MukUpFilesystem
    MukDownFilesystem
    MukUpFastFilesystem
    MukDownFastFilesystem

    MukUpPlaylist
    MukDownPlaylist
    MukUpFastPlaylist
    MukDownFastPlaylist

    MukShuffle
    MukUnShuffle
    MukRemoveSong
    MukDirUp
    MukAddStuff
    MukVolumeUp
    MukVolumeDown
    MukMuteToggle
    MukVideoToggle