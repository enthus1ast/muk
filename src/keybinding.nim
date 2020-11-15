import tables
import illwill
import events
import hashes

proc hash(key: Key): Hash =
  return hash($key)

type
  Keybinding* = Table[Key, MukEvent]

proc defaultKeybindingGlobal*(): Keybinding =
  result[Key.Right] = MukSeekForward
  result[Key.L] = MukSeekForward
  result[Key.Left] = MukSeekBackward
  result[Key.H] = MukSeekBackward

  result[Key.ShiftL] = MukSeekForwardFast
  result[Key.ShiftH] = MukSeekBackwardFast
  result[Key.RightBracket] = MukSeekForwardFast
  result[Key.LeftBracket] = MukSeekBackwardFast

  result[Key.P] = MukPauseToggle
  result[Key.Space] = MukPauseToggle

  result[Key.Tab] = MukSwitchPane

  result[Key.I] = MukDebugInfo

  result[Key.ShiftK] = MukPrevFromPlaylist
  result[Key.ShiftJ] = MukNextFromPlaylist
  result[Key.ShiftC] = MukClearPlaylist

  result[Key.S] = MukShuffle
  result[Key.ShiftS] = MukUnShuffle

  result[Key.Colon] = MukDirUp
  result[Key.Backspace] = MukDirUp

  result[Key.Plus] = MukVolumeUp
  result[Key.Minus] = MukVolumeDown

  result[Key.M] = MukMuteToggle

  result[Key.V] = MukVideoToggle

  result[Key.Home] = MukToMusicDir1
  result[Key.Zero] = MukToMusicDir1

  result[Key.One] = MukToMusicDir1
  result[Key.Two] = MukToMusicDir2
  result[Key.Three] = MukToMusicDir3
  result[Key.Four] = MukToMusicDir4

  result[Key.R] = MukCycleRepeat

  result[Key.Comma] = MukFilesystemLocal
  result[Key.Dot] = MukFilesystemRemote

  result[Key.Q] = MukQuitGui
  result[Key.ShiftQ] = MukQuitAll

  result[Key.Enter] = MukAction

  result[Key.T] = MukToggleFullscreenWidget


proc defaultKeybindingPlaylist*(): Keybinding =
  result = defaultKeybindingGlobal()
  result[Key.J] = MukDownPlaylist
  result[Key.Down] = MukDownPlaylist
  result[Key.K] = MukUpPlaylist
  result[Key.Up] = MukUpPlaylist
  result[Key.PageUp] = MukUpFastPlaylist
  result[Key.PageDown] = MukDownFastPlaylist
  result[Key.D] = MukRemoveSong
  result[Key.O] = MukSelectCurrentSongPlaylist


proc defaultKeybindingFilesystem*(): Keybinding =
  result = defaultKeybindingGlobal()
  result[Key.J] = MukDownFilesystem
  result[Key.Down] = MukDownFilesystem
  result[Key.K] = MukUpFilesystem
  result[Key.Up] = MukUpFilesystem
  result[Key.PageUp] = MukUpFastFilesystem
  result[Key.PageDown] = MukDownFastFilesystem
  result[Key.G] = MukSearchOpen
  result[Key.Slash] = MukSearchOpen
  result[Key.A] = MukAddStuff

proc defaultKeybindingSearch*(): Keybinding =
  result[Key.Escape] = MukSearchCancel
  result[Key.Enter] = MukSearchDone
  result[Key.Up] = MukSearchDone
  result[Key.Down] = MukSearchDone
  result[Key.PageUp] = MukSearchDone
  result[Key.PageDown] = MukSearchDone

proc toMukEvent*(keybinding: Keybinding, key: Key): MukEvent =
  return keybinding.getOrDefault(key, MukUnknown)

