## https://github.com/mpv-player/mpv/blob/master/etc/input.conf
# --display-tags  String list (default: Artist,Album,Album_Artist,Comment,Composer,Date,Description,Genre,Performer,Rating,Series,Title,Track,icy-title,service_name)
var doRender = 0
var idleSteps = 0
import os
import mpv
import asyncdispatch
import illwill
import illwillWidgets
import strutils
import sequtils
import json
import parsecfg
import templates
import mukc
import tables
import stack

import filesys
import mpvcontrol

import network, messages
import times
# import search
import tplaylist
import trepeatKind

import keybinding, events


type
  InWidget {.pure.} = enum
    Playlist, Filesystem, Search
  FilesystemKind {.pure.} = enum
    Local, Remote
  Muk = ref object
    mukc: Mukc
    cs: ClientStatus
    fs: Filesystem
    tb: TerminalBuffer
    config: Config
    debugInfo: bool
    inWidget: InWidget
    inWidgetStack: Stack[InWidget]
    lastSelectedIdx: Table[string, int]
    filesystemKind: FilesystemKind
    # currentSongInfo: SongInfo

    # Gui widgets
    filesystem: ChooseBox
    playlist: ChooseBox
    infLog: InfoBox
    infSongPath: InfoBox
    progSongProgress: ProgressBar
    btnPlayPause: Button
    txtSearch: TextBox

    progVolume: ProgressBar


    # Repeat modes
    radGroupRep: RadioBoxGroup
    radRepNone: Checkbox
    radRepSong: Checkbox
    radRepList: Checkbox

    # Remote or local filesystem
    radGroupFilesys: RadioBoxGroup
    radFilesysLocal: Checkbox
    radFilesysRemote: Checkbox


    # Keybinding
    # TODO maybe do two/three keebindings for Filesystem/Playlist/help etc..
    keybindingPlaylist: Keybinding
    keybindingFilesystem: Keybinding
    keybindingSearch: Keybinding

    musikDir1: string
    musikDir2: string
    musikDir3: string
    musikDir4: string

  SongInfo = object ## Normalized song information (mpv gives json)
    album: string
    artist: string
    title: string
    path: string

proc storeLastSelectedIndex(muk: Muk, path: string, idx: int) =
  muk.lastSelectedIdx[path] = idx

proc getLastSelectedIndex(muk: Muk, path: string): int =
  return muk.lastSelectedIdx.getOrDefault(path, 0)

proc newMuk(): Muk =
  result = Muk()
  result.config = loadConfig(getAppDir() / "config.ini")
  result.mukc = newMukc()
  ## TODO this must be in an async proc not in newMuk
  result.cs = ClientStatus()
  result.musikDir1 = result.config.getSectionValue("musicDirs", "musicDir1")
  result.musikDir2 = result.config.getSectionValue("musicDirs", "musicDir2")
  result.musikDir3 = result.config.getSectionValue("musicDirs", "musicDir3")
  result.musikDir4 = result.config.getSectionValue("musicDirs", "musicDir4")
  result.fs = newFilesystem()

  # TODO The layout IS this values are overwritten done in "layout()"
  result.filesystem = newChooseBox(@[], 1, 1, (terminalWidth() div 2) - 2, terminalHeight() - 5, color = fgGreen )
  result.playlist = newChooseBox(@[],  terminalWidth() div 2, 1, terminalWidth() div 2, terminalHeight() - 5 , color = fgGreen)
  result.infSongPath = newInfoBox("", 0, terminalHeight() - 2, terminalWidth(), 1)

  result.progSongProgress = newProgressBar("", 2, terminalHeight() - 1, terminalWidth() - 2, 0.0, 100.0, bgTodo = bgBlack)
  result.progSongProgress.color = fgWhite
  result.progSongProgress.colorText = fgYellow
  result.progSongProgress.colorTextDone = fgBlack

  result.btnPlayPause = newButton(">", 0, terminalHeight() - 1, 2, 1, false)
  result.txtSearch = newTextBox("", 0, 0, 0, color = fgWhite, bgcolor = bgCyan)

  result.progVolume = newProgressBar("", 0, 0, value = 0.0, maxValue = 130.0)
  result.progVolume.colorText = fgYellow
  result.progVolume.colorTextDone = fgBlack

  result.radRepNone = newRadioBox("NONE", 5, 5)
  result.radRepNone.color = fgWhite
  result.radRepSong = newRadioBox("SONG", 10, 10)
  result.radRepSong.color = fgWhite
  result.radRepList = newRadioBox("LIST", 15, 15)
  result.radRepList.color = fgWhite
  result.radGroupRep = newRadioBoxGroup(@[
    addr result.radRepNone, addr result.radRepSong, addr result.radRepList
  ])
  result.radRepNone.textChecked = "(X)"
  result.radRepNone.textUnchecked = "( )"
  result.radRepSong.textChecked = "(X)"
  result.radRepSong.textUnchecked = "( )"
  result.radRepList.textChecked = "(X)"
  result.radRepList.textUnchecked = "( )"

  result.radFilesysLocal = newRadioBox("LOCAL", 10, 10)
  result.radFilesysLocal.color = fgWhite
  result.radFilesysRemote = newRadioBox("REMOTE", 15, 15)
  result.radFilesysRemote.color = fgWhite
  result.radGroupFilesys = newRadioBoxGroup(@[
    addr result.radFilesysLocal, addr result.radFilesysRemote
  ])
  result.radFilesysLocal.textChecked = "(X)"
  result.radFilesysLocal.textUnchecked = "( )"
  result.radFilesysRemote.textChecked = "(X)"
  result.radFilesysRemote.textUnchecked = "( )"


  result.infLog = newInfoBox("logbox", terminalWidth() div 3, 1, terminalWidth() div 3, 10)
  result.infLog.wrapMode = WrapMode.Char

  # setControlCHook(exitProc)
  illwillInit(fullScreen = true, mouse = true)
  hideCursor()

  result.tb = newTerminalBuffer(terminalWidth(), terminalHeight())

  result.keybindingPlaylist = defaultKeybindingPlaylist()
  result.keybindingFilesystem = defaultKeybindingFilesystem()
  result.keybindingSearch = defaultKeybindingSearch()

proc layout(muk: Muk) =
  muk.filesystem.x = 0
  muk.filesystem.y = 0
  muk.filesystem.w = (terminalWidth() div 2) - 2
  muk.filesystem.h = terminalHeight() - 4

  muk.playlist.x = (terminalWidth() div 2) - 1
  muk.playlist.y = 0
  muk.playlist.w = terminalWidth() div 2
  muk.playlist.h = terminalHeight() - 4

  muk.radRepNone.x = 0
  muk.radRepNone.y = terminalHeight() - 3
  muk.radRepSong.x = 8
  muk.radRepSong.y = terminalHeight() - 3
  muk.radRepList.x = 16
  muk.radRepList.y = terminalHeight() - 3

  muk.radFilesysLocal.x = 26
  muk.radFilesysLocal.y = terminalHeight() - 3
  muk.radFilesysRemote.x = 35
  muk.radFilesysRemote.y = terminalHeight() - 3

  muk.infLog.x = terminalWidth() div 2
  muk.infLog.y = 1
  muk.infLog.w = terminalWidth() div 3
  muk.infLog.h = 10

  muk.infSongPath.x = 0
  muk.infSongPath.y = terminalHeight() - 2
  muk.infSongPath.w = terminalWidth()
  muk.infSongPath.h = 1

  muk.progSongProgress.x = 2
  muk.progSongProgress.y = terminalHeight() - 1
  muk.progSongProgress.l = terminalWidth() - 2

  muk.btnPlayPause.x = 0
  muk.btnPlayPause.y = terminalHeight() - 1
  muk.btnPlayPause.w = 2
  muk.btnPlayPause.h = 1

  muk.txtSearch.x = 1
  muk.txtSearch.y = terminalHeight() - 4
  muk.txtSearch.w = (terminalWidth() div 2) - 3

  muk.progVolume.x = terminalWidth() - 13
  muk.progVolume.y = terminalHeight() - 3
  muk.progVolume.l = 10


proc foo(muk: Muk) {.async.} =
  while true:
    await sleepAsync(5000)
    muk.tb.clear(" ")
    muk.tb.display()
    muk.layout()
    # echo "foo"

proc banner(muk: Muk) =
  muk.tb.write 10, 3, "                  __    ";
  muk.tb.write 10, 4, ".--------..--.--.|  |--.";
  muk.tb.write 10, 5, "|        ||  |  ||    < ";
  muk.tb.write 10, 6, "|__|__|__||_____||__|__|";
  muk.tb.write 10, 7, "                        ";
  muk.tb.write 10, 8, "  prototype             ";
  muk.tb.write 10, 9, "PRESS ENTER TO CONTINUE ";
  muk.tb.write 10, 10,"(THIS SAVES CPU CYLCES) ";

proc exitProc() {.noconv.} =
  illwillDeinit()
  showCursor()
  quit(0)

proc log(muk: Muk, msg: string) =
  muk.infLog.text = (msg & "\n" & muk.infLog.text)
  muk.infLog.text.setLen(1500)

proc getProgressInPercent(muk: Muk): float =
  result = 0.0
  tryIgnore: result = muk.cs.progress.percent.clamp(0.0, 100.0)

proc doColorSchema(tb: var TerminalBuffer) =
  tb.setBackgroundColor(bgBlack)
  tb.setForegroundColor(fgGreen)
  tb.clear(" ")

proc fillPlaylistWidget(chooseBox: var ChooseBox, playlistSongs: PlaylistSongs) =
  chooseBox.elements = @[]
  for idx, song in playlistSongs:
    chooseBox.elements.add song.filename
    if song.current:
      chooseBox.highlightIdx = idx

proc formatDuration(dur: Duration): string =
  let dp = dur.toParts()
  result &= ($dp[Hours]).align(2, '0') & ":"
  result &= ($dp[Minutes]).align(2, '0') & ":"
  result &= ($dp[Seconds]).align(2, '0')

proc infoCurrentSongDurationSeconds(muk: Muk): string =
  result = ""
  tryIgnore:
    # let curPos = initDuration(milliseconds = (parseFloat(muk.ctx.get_property("time-pos")) * 1000.00).int )
    # let duration = initDuration(milliseconds = (parseFloat(muk.ctx.get_property("duration")) * 1000.00).int )
    let curPos = initDuration(milliseconds = (muk.cs.progress.timePos * 1000.00).int)
    let duration = initDuration(milliseconds = (muk.cs.progress.duration * 1000.00).int)
    result &= $curPos.formatDuration
    result &= "/"
    result &= $duration.formatDuration

proc fillFilesystem(filesystem: var ChooseBox, elems: seq[string]) =
  # TODO test if this is neccasary
  filesystem.elements.setLen(0)
  for elem in elems:
    filesystem.elements.add elem

proc filesystemOpenDir(muk: Muk, dir: string) =
  ## Points the filesystem to the given `dir`
  muk.fs.currentPath = dir
  muk.filesystem.fillFilesystem(muk.fs.ls)

proc openAction(muk: Muk) =
  if muk.inWidget == InWidget.Playlist:
    asyncCheck muk.mukc.playlistPlayIndex(muk.playlist.choosenidx)
    # muk.ctx.command(@["playlist-play-index", $muk.playlist.choosenidx])
    discard # TODO
  elif muk.inWidget == InWidget.Filesystem:
    var act = muk.fs.action(muk.filesystem.element())
    muk.infSongPath.text = muk.fs.currentPath & "|" & $act #fs # filesystem.element()
    case act.kind
    of ActionKind.File:
      # muk.mukc
      # muk.ctx.addToPlaylistAndPlay(muk.fs.currentPath / muk.filesystem.element())
      discard # TODO
    of ActionKind.Folder:
      muk.filesystem.choosenidx = 0
      muk.filesystemOpenDir(act.folderPath)
      muk.filesystem.filter = ""
      muk.filesystem.choosenidx = muk.getLastSelectedIndex(muk.fs.currentPath)
    else:
      discard

proc quitGui(muk: Muk) =
  muk.tb.resetAttributes()
  illwillDeinit()
  showCursor()
  echo "muk, made with ♥, mpv and Nim. Star us on github :), http://github.com/enthus1ast/muk/"
  quit(0)

proc handleKeyboard(muk: Muk, key: var Key) =
  var mev: MukEvent
  case muk.inWidget
  of InWidget.Playlist:
    mev = muk.keybindingPlaylist.toMukEvent(key)
  of InWidget.Filesystem:
    mev = muk.keybindingFilesystem.toMukEvent(key)
  of InWidget.Search:
    mev = muk.keybindingSearch.toMukEvent(key)

  muk.log($mev)

  case mev
  of MukQuitAll, MukQuitGui:
    muk.quitGui()
  of MukPauseToggle:
    discard muk.mukc.togglePause()
  of MukSeekForward:
    asyncCheck muk.mukc.setSeekRelative(3)
  of MukSeekBackward:
    asyncCheck muk.mukc.setSeekRelative(-3)
  of MukSeekForwardFast:
    asyncCheck muk.mukc.setSeekRelative(15)
  of MukSeekBackwardFast:
    asyncCheck muk.mukc.setSeekRelative(-15)
  of MukSwitchPane:
    case muk.inWidget
    of InWidget.Playlist:
      muk.inWidget = InWidget.Filesystem
    of InWidget.Filesystem:
      muk.inWidget = InWidget.Playlist
    of InWidget.Search:
      discard
  of MukDebugInfo:
    muk.debugInfo = not muk.debugInfo
  of MukPrevFromPlaylist:
    asyncCheck muk.mukc.prevFromPlaylist()
  of MukNextFromPlaylist:
    asyncCheck muk.mukc.nextFromPlaylist()
  of MukClearPlaylist:
    asyncCheck muk.mukc.clearPlaylist()
  of MukDownPlaylist:
    muk.playlist.nextChoosenidx()
  of MukUpPlaylist:
    muk.playlist.prevChoosenidx()
  of MukUpFastPlaylist:
    muk.playlist.prevChoosenidx(10)
  of MukDownFastPlaylist:
    muk.playlist.nextChoosenidx(10)

  of MukDownFilesystem:
    muk.filesystem.nextChoosenidx()
    muk.storeLastSelectedIndex(muk.fs.currentPath, muk.filesystem.choosenidx)
  of MukUpFilesystem:
    muk.filesystem.prevChoosenidx()
    muk.storeLastSelectedIndex(muk.fs.currentPath, muk.filesystem.choosenidx)
  of MukUpFastFilesystem:
    muk.filesystem.prevChoosenidx(10)
    muk.storeLastSelectedIndex(muk.fs.currentPath, muk.filesystem.choosenidx)
  of MukDownFastFilesystem:
    muk.filesystem.nextChoosenidx(10)
    muk.storeLastSelectedIndex(muk.fs.currentPath, muk.filesystem.choosenidx)
  of MukToMusicDir1:
    muk.filesystemOpenDir(muk.musikDir1)
    muk.filesystem.choosenidx = muk.getLastSelectedIndex(muk.fs.currentPath)
  of MukToMusicDir2:
    muk.filesystemOpenDir(muk.musikDir2)
  of MukToMusicDir3:
    muk.filesystemOpenDir(muk.musikDir3)
  of MukToMusicDir4:
    muk.filesystemOpenDir(muk.musikDir4)

  of MukShuffle:
    # muk.ctx.command("playlist-shuffle")
    discard # TODO
  of MukUnShuffle:
    # muk.ctx.command("playlist-unshuffle")
    discard # TODO
  of MukRemoveSong:
    asyncCheck muk.mukc.removeSong(muk.playlist.choosenIdx)
  of MukDirUp:
    muk.fs.up()
    # muk.filesystem.choosenidx = 0
    muk.filesystemOpenDir(muk.fs.currentPath)
    muk.filesystem.choosenidx = muk.getLastSelectedIndex(muk.fs.currentPath)
    muk.filesystem.filter = ""
  of MukAddStuff:
    asyncCheck muk.mukc.loadRemoteFile(muk.fs.currentPath / muk.filesystem.element(), append = true)
    muk.filesystem.nextChoosenidx()
    discard # TODO
  of MukVolumeUp:
    asyncCheck muk.mukc.setVolumeRelative(5)
  of MukVolumeDown:
    asyncCheck muk.mukc.setVolumeRelative(-5)
  of MukMuteToggle:
    asyncCheck muk.mukc.toggleMute()
  of MukSearchOpen:
    muk.inWidget = InWidget.Search
    muk.txtSearch.focus = true
    setKeyAsHandled(key)
  of MukSearchDone:
    muk.log(muk.txtSearch.text)
    muk.inWidget = InWidget.Filesystem # TODO inWidgetStack
    muk.txtSearch.focus = false
    muk.txtSearch.text = ""
    muk.txtSearch.caretIdx = 0 # TODO bug in illwillWidgets
    muk.filesystem.choosenidx = 0
    setKeyAsHandled(key)
  of MukSearchCancel:
    muk.inWidget = InWidget.Filesystem
    muk.txtSearch.focus = false
    muk.txtSearch.text = ""
    muk.txtSearch.caretIdx = 0 # TODO bug in illwillWidgets
    muk.filesystem.filter = ""
  of MukVideoToggle:
    # muk.ctx.command(@["cycle", "video"])
    discard # TODO
  of MukCycleRepeat:
    asyncCheck muk.mukc.cylceRepeat()
  of MukFilesystemLocal:
    muk.filesystemKind = FilesystemKind.Local
  of MukFilesystemRemote:
    muk.filesystemKind = FilesystemKind.Remote
  of MukSelectCurrentSongPlaylist:
    muk.playlist.choosenIdx = muk.playlist.highlightIdx
  else:
    discard

  ## TODO
  if key == Key.T:
    # tryLog muk.log(muk.ctx.get_property("filtered-metadata"))
    # tryLog muk.log(muk.ctx.get_property("metadata"))
    discard # TODO
  if key == Key.Space:
    # muk.ctx.command("loadfile", """C:\Users\david\ttt.mp4""")
    # muk.ctx.command(@["playlist-play-index", "0"])
    # discard muk.ctx.togglePause() # TODO
    # muk.ctx.loadfile(playlist.currentSong())
    discard

  if key == Key.Enter:
    muk.openAction()


proc handleMouse(muk: Muk, key: Key) =
  let coords = getMouse()
  var ev: Events

  if muk.debugInfo:
    muk.log(coords.positionHelper())

  ## Seek in song
  ev = muk.tb.dispatch(muk.progSongProgress, coords)
  if ev.contains MouseDown:
    asyncCheck muk.mukc.setProgressInPercent(muk.progSongProgress.valueOnPos(coords))

  ## Click on pause
  ev = muk.tb.dispatch(muk.btnPlayPause, coords)
  if ev.contains MouseDown:
    asyncCheck muk.mukc.togglePause()

  ## Add filesystem file to playlist
  ev = muk.tb.dispatch(muk.filesystem, coords)
  if (ev.contains MouseDown) and (coords.button == mbLeft):
    muk.inWidget = InWidget.Filesystem
  if (ev.contains MouseDown) and (coords.button == mbRight):
    muk.inWidget = InWidget.Filesystem
    muk.openAction()

  ## Play file from playlist
  ev = muk.tb.dispatch(muk.playlist, coords)
  if (ev.contains MouseDown) and (coords.button == mbLeft):
    muk.inWidget = InWidget.Playlist
  if (ev.contains MouseDown) and (coords.button == mbRight):
    muk.inWidget = InWidget.Playlist
    muk.log(muk.playlist.element())
    asyncCheck muk.mukc.playlistPlayIndex(muk.playlist.choosenidx)
    discard # TODO

  # Repeat chkbox
  # TODO mouse disabled for now, only RPC for cycle RepeatKind (r) atm.
  # ev = muk.tb.dispatch(muk.radGroupRep, coords)

  ## Search
  if muk.inWidget == InWidget.Search:
    ev = muk.tb.dispatch(muk.txtSearch, coords)

proc renderCurrentSongInfo(muk: Muk): string =
  result = ""
  result &= muk.cs.metadata.artist & " - "
  result &= muk.cs.metadata.album & " - "
  result &= muk.cs.metadata.title & " | "
  result &= muk.cs.metadata.path

proc main(): int =
  var muk = newMuk()
  if waitFor muk.mukc.connect("127.0.0.1", 8889.Port):
  # if waitFor muk.mukc.connect("192.168.1.107", 8889.Port):
  # if waitFor muk.mukc.connect("192.168.2.204", 8889.Port):
    if waitFor muk.mukc.authenticate("foo", "baa"):
      asyncCheck muk.mukc.collectFanouts(muk.cs)

  # muk.banner()
  # muk.tb.display()
  # sleep(1500)

  result = 1

  muk.filesystemOpenDir(getCurrentDir().absolutePath())
  muk.layout()
  var oldDimenions = terminalSize()

  while true:
    if oldDimenions != terminalSize():
      muk.tb = newTerminalBuffer(terminalSize().w, terminalSize().h)
      muk.tb.clear(" ")
      muk.tb.display()
      muk.layout()
      sleep(50)
      oldDimenions = terminalSize()

    var key = getKey()
    if key == Key.None:
      discard
      idleSteps.inc
    elif key == Key.Mouse:
      muk.handleMouse(key)
    else:
      muk.handleKeyboard(key)
      idleSteps = 0

    # if idleSteps > 500:
    #   # "CPU saver" until illwill can do blocking reads
    #   muk.banner()
    #   muk.tb.display()
    #   discard stdin.readLine()
    #   idleSteps = 0

    # Special case for search
    if muk.txtSearch.focus:
      muk.log(muk.txtSearch.text)
      muk.filesystem.filter = muk.txtSearch.text
      if muk.tb.handleKey(muk.txtSearch, key):
        muk.log("key handled: " & muk.txtSearch.text)

    muk.infSongPath.text = muk.renderCurrentSongInfo()

    muk.progSongProgress.value = muk.getProgressInPercent()
    muk.progSongProgress.text = muk.infoCurrentSongDurationSeconds()  #$ctx.getProgressInPercent()

    if muk.cs.pause:
      muk.btnPlayPause.text = "||"
      muk.btnPlayPause.color = fgYellow
    else:
      muk.btnPlayPause.text = ">>" # $($ctx.getPause())[0]
      muk.btnPlayPause.color = fgGreen

    muk.filesystem.title = muk.fs.currentPath
    muk.playlist.title = "Unnamed playlist (todo)"

    muk.filesystem.highlight = muk.inWidget == InWidget.Filesystem
    muk.filesystem.chooseEnabled = muk.inWidget == InWidget.Filesystem
    muk.playlist.highlight = muk.inWidget == InWidget.Playlist
    muk.playlist.chooseEnabled = muk.inWidget == InWidget.Playlist

    muk.progVolume.value = muk.cs.volume
    if muk.cs.mute:
      muk.progVolume.text = "muted"
    else:
      muk.progVolume.text = $muk.cs.volume & "%"

    muk.playlist.fillPlaylistWidget(muk.cs.playlist) # TODO not every tick...

    # The repeat radio buttons
    muk.radGroupRep.uncheckAll()
    case muk.cs.repeatKind
    of RepeatKind.None:
      muk.radRepNone.checked = true
    of RepeatKind.Song:
      muk.radRepSong.checked = true
    of RepeatKind.List:
      muk.radRepList.checked = true

    # The Local and Remote filesystem radio buttons
    muk.radGroupFilesys.uncheckAll()
    case muk.filesystemKind
    of FilesystemKind.Local:
      muk.radFilesysLocal.checked = true
    of FilesystemKind.Remote:
      muk.radFilesysRemote.checked = true


    doRender.inc
    if doRender >= 0: # test if less rendering is also still good
      doRender = 0
      try:
        muk.tb.render(muk.filesystem)
        muk.tb.render(muk.playlist)
        muk.tb.render(muk.infSongPath)
        muk.tb.render(muk.progSongProgress)
        muk.tb.render(muk.progVolume)
        muk.tb.render(muk.btnPlayPause)
        if muk.inWidget == InWidget.Search:
          muk.tb.render(muk.txtSearch)
        if muk.debugInfo:
          muk.tb.render(muk.infLog)

        muk.tb.render(muk.radGroupRep)
        muk.tb.render(muk.radGroupFilesys)
        muk.tb.write(24, terminalHeight() - 3, "|")
        # muk.tb.render(muk.chkRepeat)
        # muk.tb.render(muk.chkNext)
        muk.tb.display()
      except:
        echo "COULD NOT RENDER"
        echo getCurrentExceptionMsg()
    poll(35)
  return 0

system.quit(main())
