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
import filesys
import sequtils
import json
import parsecfg
import templates
import mukc

import stack
import mpvcontrol
import network, messages
# import search
import tplaylist

import keybinding, events


type
  InWidget {.pure.} = enum
    Playlist, Filesystem, Search

  Muk = ref object
    mukc: Mukc
    cs: ClientStatus
    fs: Filesystem
    tb: TerminalBuffer
    config: Config
    debugInfo: bool
    inWidget: InWidget
    inWidgetStack: Stack[InWidget]
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
  result.btnPlayPause = newButton(">", 0, terminalHeight() - 1, 2, 1, false)
  result.txtSearch = newTextBox("", 0, 0, 0, color = fgWhite, bgcolor = bgCyan)
  result.progVolume = newProgressBar("", 0, 0, value = 0.0, maxValue = 100.0)


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
  muk.filesystem.x = 1
  muk.filesystem.y = 1
  muk.filesystem.w = (terminalWidth() div 2) - 2
  muk.filesystem.h = terminalHeight() - 5

  muk.playlist.x = terminalWidth() div 2
  muk.playlist.y = 1
  muk.playlist.w = terminalWidth() div 2
  muk.playlist.h = terminalHeight() - 5

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

  muk.txtSearch.x = 0
  muk.txtSearch.y = terminalHeight() - 3
  muk.txtSearch.w = terminalWidth() div 2

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
      chooseBox.highlightIdx = idx #song.id - 1


import times

proc formatDuration(dur: Duration): string =
  let dp = dur.toParts()
  result &= ($dp[Hours]).align(2, '0') & ":"
  result &= ($dp[Minutes]).align(2, '0') & ":"
  result &= ($dp[Seconds]).align(2, '0')
  # result &= ($dp[Milliseconds]).align(3, '0')


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
# proc addSelectedItemToPlaylist

proc filesystemOpenDir(muk: Muk, dir: string) =
  ## Points the filesystem to the given `dir`
  muk.fs.currentPath = dir
  muk.filesystem.fillFilesystem(muk.fs.ls)

proc openAction(muk: Muk) =
  if muk.inWidget == InWidget.Playlist:
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
    # muk.ctx.prevFromPlaylist()
    discard # TODO
  of MukNextFromPlaylist:
    # muk.ctx.nextFromPlaylist()
    discard # TODO
  of MukClearPlaylist:
    # muk.ctx.clearPlaylist()
    discard # TODO

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
  of MukUpFilesystem:
    muk.filesystem.prevChoosenidx()
  of MukUpFastFilesystem:
    muk.filesystem.prevChoosenidx(10)
  of MukDownFastFilesystem:
    muk.filesystem.nextChoosenidx(10)

  of MukToMusicDir1:
    muk.filesystemOpenDir(muk.musikDir1)
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
    # tryIgnore muk.ctx.command("playlist-remove", $muk.playlist.choosenIdx)
    discard # TODO
  of MukDirUp:
    muk.fs.up()
    muk.filesystem.choosenidx = 0
    muk.filesystemOpenDir(muk.fs.currentPath)
    muk.filesystem.filter = ""
  of MukAddStuff:
    asyncCheck muk.mukc.loadRemoteFile(muk.fs.currentPath / muk.filesystem.element(), append = true)
    muk.filesystem.nextChoosenidx()
    discard # TODO
  of MukVolumeUp:
    asyncCheck muk.mukc.setVolumeRelative(20)
  of MukVolumeDown:
    asyncCheck muk.mukc.setVolumeRelative(-20)
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
    # muk.ctx.command("loadfile", """C:\Users\david\Music\2016 - Nonagon Infinity\01. Robot Stop.mp3""")
    muk.openAction()


proc handleMouse(muk: Muk, key: Key) =
  let coords = getMouse()
  # muk.log($coords)
  var ev: Events

  ## Seek in song
  ev = muk.tb.dispatch(muk.progSongProgress, coords)
  if ev.contains MouseDown:
    asyncCheck muk.mukc.setProgressInPercent(muk.progSongProgress.valueOnPos(coords))
    # var cnt: Control_Client_SEEKRELATIVE
    # cnt =
    #  muk.progSongProgress.valueOnPos(coords))
    # muk.mukc.control.send

  ## Click on pause
  ev = muk.tb.dispatch(muk.btnPlayPause, coords)
  if ev.contains MouseDown:
    discard muk.mukc.togglePause()
    discard # TODO

  ## Add filesystem file to playlist
  ev = muk.tb.dispatch(muk.filesystem, coords)
  if (ev.contains MouseDown) and (coords.button == mbRight):
    muk.inWidget = InWidget.Filesystem
    muk.openAction()

  ## Play file from playlist
  ev = muk.tb.dispatch(muk.playlist, coords)
  if (ev.contains MouseDown) and (coords.button == mbRight):
    muk.inWidget = InWidget.Playlist
    muk.log(muk.playlist.element())
    # muk.ctx.play (playlist.element())
    # muk.ctx.command(@["playlist-play-index", $muk.playlist.choosenidx])
    discard # TODO

  ## Search
  if muk.inWidget == InWidget.Search:
    ev = muk.tb.dispatch(muk.txtSearch, coords)
    # if (ev.contains MouseDown) and (coords.button == mbRight):
    #   muk.inWidget = InWidget.Playlist
    #   muk.log(muk.playlist.element())
    #   # muk.ctx.play (playlist.element())
    #   muk.ctx.command(@["playlist-play-index", $muk.playlist.choosenidx])


  # ev = muk.tb.dispatch(muk.playlist, coords)
  # if (ev.contains MouseDown) and (coords.button == mbRight):

proc renderCurrentSongInfo(muk: Muk): string =
  result = ""
  result &= muk.cs.metadata.artist & " - "
  result &= muk.cs.metadata.album & " - "
  result &= muk.cs.metadata.title & " | "
  result &= muk.cs.metadata.path


proc main(): int =
  var muk = newMuk()

  if waitFor muk.mukc.connect("127.0.0.1", 8889.Port):
    if waitFor muk.mukc.authenticate("foo", "baa"):
      asyncCheck muk.mukc.collectFanouts(muk.cs)

  # muk.banner()
  # muk.tb.display()
  # sleep(1500)

  # asyncCheck foo(muk)
  ## Testing
  # muk.ctx.addToPlaylist """C:\Users\david\ttt.mp4"""
  # muk.ctx.addToPlaylist """C:\Users\david\Music\2016 - Nonagon Infinity\01. Robot Stop.mp3"""
  result = 1
  # var currentPath = """C:\Users\david\Music\2016 - Nonagon Infinity\"""

  # var currentPath = """D:\audio_books\Der Herr der Ringe (Hörbuch)\Der Herr der Ringe - Band 1 - Die Gefährten\"""
  # var currentPath = """D:/backup/IBC_new_2020_07_29/public/files/2019-08/"""
  # muk.fs.currentPath = currentPath
  muk.filesystemOpenDir(getCurrentDir().absolutePath())
  muk.layout()
  var oldDimenions = terminalSize()

  while true:


    if oldDimenions != terminalSize():
      # for idx in 0 .. 3:
      muk.tb = newTerminalBuffer(terminalSize().w, terminalSize().h)
      muk.tb.clear(" ")
      muk.tb.display()
      muk.layout()
      sleep(50)
      oldDimenions = terminalSize()
    # let event = muk.ctx.wait_event(0) # TODO
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


    # try:
    #   let mpvevent = mpv.event_name(event.event_id)
    #   if mpvevent != "none":
    #     muk.log($mpvevent)
    #   if mpvevent == "end-file":
    #     discard
    #   if mpvevent == "metadata-update":
    #     let rawMetadata = muk.ctx.getMetadata()
    #     muk.log($rawMetadata)
    #     let songInfo = rawMetadata.normalizeMetadata()
    #     muk.log(repr songInfo)
    #     muk.currentSongInfo = songInfo
    #     muk.currentSongInfo.path = muk.ctx.getSongPath()
    #   if event.event_id == mpv.EVENT_SHUTDOWN:
    #     break
    # except:
    #   discard


    # muk.infSongPath.text = muk.getSongTitle() & " | " & muk.getSongPath()
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

    muk.playlist.fillPlaylistWidget(muk.cs.playlist) # TODO not every tick...

    doRender.inc
    if doRender >= 4: # test if less rendering is also still good
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
        muk.tb.display()
      except:
        echo "COULD NOT RENDER"
        echo getCurrentExceptionMsg()

    # sleep(35)
    poll(35)


  return 0


system.quit(main())
