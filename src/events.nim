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

    MukToMusicDir1
    MukToMusicDir2
    MukToMusicDir3
    MukToMusicDir4

    MukQuitGui
    MukQuitAll

    MukSelectCurrentSongPlaylist

    MukSearchOpen
    MukSearchCancel
    MukSearchDone

    MukCycleRepeat

    MukFilesystemLocal
    MukFilesystemRemote

    MukAction