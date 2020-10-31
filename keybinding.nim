import tables
import illwill
import events
type
  Keybinding* = Table[Key, MukEvent]

proc defaultKeybindingGlobal*(): Keybinding =
  result[Key.Right] = MukSeekForward
  result[Key.L] = MukSeekForward

  result[Key.Left] = MukSeekBackward
  result[Key.H] = MukSeekBackward

  result[Key.ShiftL] = MukSeekForwardFast
  result[Key.ShiftH] = MukSeekBackwardFast

  result[Key.P] = MukPauseToggle

  result[Key.Tab] = MukSwitchPane

  result[Key.I] = MukDebugInfo

  result[Key.ShiftK] = MukPrevFromPlaylist
  result[Key.ShiftJ] = MukNextFromPlaylist
  result[Key.C] = MukClearPlaylist

  result[Key.S] = MukShuffle
  result[Key.ShiftS] = MukUnShuffle

  result[Key.Colon] = MukDirUp

  result[Key.Plus] = MukVolumeUp
  result[Key.Minus] = MukVolumeDown

  result[Key.M] = MukMuteToggle

  result[Key.V] = MukVideoToggle

proc defaultKeybindingPlaylist*(): Keybinding =
  result = defaultKeybindingGlobal()
  result[Key.J] = MukDownPlaylist
  result[Key.Down] = MukDownPlaylist
  result[Key.K] = MukUpPlaylist
  result[Key.Up] = MukUpPlaylist
  result[Key.PageUp] = MukUpFastPlaylist
  result[Key.PageDown] = MukDownFastPlaylist
  result[Key.D] = MukRemoveSong

proc defaultKeybindingFilesystem*(): Keybinding =
  result = defaultKeybindingGlobal()
  result[Key.J] = MukDownFilesystem
  result[Key.Down] = MukDownFilesystem
  result[Key.K] = MukUpFilesystem
  result[Key.Up] = MukUpFilesystem
  result[Key.PageUp] = MukUpFastFilesystem
  result[Key.PageDown] = MukDownFastFilesystem
  result[Key.A] = MukAddStuff


proc toMukEvent*(keybinding: Keybinding, key: Key): MukEvent =
  return keybinding.getOrDefault(key, MukUnknown)

