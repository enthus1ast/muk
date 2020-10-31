## https://github.com/mpv-player/mpv/blob/master/etc/input.conf

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

import keybinding, events


type
  Muk = ref object
    ctx: ptr handle ## the libmpv context
    inPlaylist: bool
    fs: Filesystem
    tb: TerminalBuffer
    config: Config

    # Gui widgets
    filesystem: ChooseBox
    playlist: ChooseBox
    infLog: InfoBox
    infSongPath: InfoBox
    progSongProgress: ProgressBar
    btnPlayPause: Button

    # Keybinding
    # TODO maybe do two/three keebindings for Filesystem/Playlist/help etc..
    keybindingPlaylist: Keybinding
    keybindingFilesystem: Keybinding

    musikDir1: string
    musikDir2: string
    musikDir3: string
    musikDir4: string

proc newMuk(): Muk =
  result = Muk()
  result.config = loadConfig(getAppDir() / "config.ini")
  result.musikDir1 = result.config.getSectionValue("musicDirs", "musicDir1")
  result.musikDir2 = result.config.getSectionValue("musicDirs", "musicDir2")
  result.musikDir3 = result.config.getSectionValue("musicDirs", "musicDir3")
  result.musikDir4 = result.config.getSectionValue("musicDirs", "musicDir4")
  result.ctx = mpv.create()
  if result.ctx.isNil:
    echo "failed creating mpv context"
    return
  # defer: mpv.terminate_destroy(result.ctx) # must be in muk destructor
  result.ctx.set_option("terminal", "no")
  result.ctx.set_option("video", "no")
  result.ctx.set_option("input-default-bindings", "yes")
  result.ctx.set_option("input-vo-keyboard", "no")
  result.ctx.set_option("osc", true)
  check_error result.ctx.initialize()
  result.fs = newFilesystem()

  # TODO The layout should be done in "layout()"
  result.filesystem = newChooseBox(@[], 1, 1, (terminalWidth() div 2) - 2, terminalHeight() - 5, color = fgGreen )
  result.playlist = newChooseBox(@[],  terminalWidth() div 2, 1, terminalWidth() div 2, terminalHeight() - 5 , color = fgGreen)
  result.infLog = newInfoBox("logbox", terminalWidth() div 2, 1, terminalWidth() div 3, 10)
  result.infSongPath = newInfoBox("", 0, terminalHeight() - 2, terminalWidth(), 1)
  result.progSongProgress = newProgressBar("", 2, terminalHeight() - 1, terminalWidth() - 2, 0.0, 100.0, bgTodo = bgBlack)
  result.progSongProgress.color = fgWhite
  result.progSongProgress.colorText = fgRed
  result.btnPlayPause = newButton(">", 0, terminalHeight() - 1, 2, 1, false)

  # asyncCheck foo()
  # setControlCHook(exitProc)
  illwillInit(fullScreen = true, mouse = true)
  hideCursor()

  result.tb = newTerminalBuffer(terminalWidth(), terminalHeight())

  result.keybindingPlaylist = defaultKeybindingPlaylist()
  result.keybindingFilesystem = defaultKeybindingFilesystem()

proc foo() {.async.} =
  while true:
    await sleepAsync(1000)
    # echo "foo"

proc exitProc() {.noconv.} =
  illwillDeinit()
  showCursor()
  quit(0)

template tryIgnore(body: untyped) =
  try:
    body
  except:
    discard

proc getProgressInPercent(muk: Muk): float =
  result = 0.0
  tryIgnore: result = (parseFloat muk.ctx.get_property("percent-pos")).clamp(0.0, 100.0)

proc setProgressInPercent(muk: Muk, progress: float) =
  tryIgnore: muk.ctx.set_property("percent-pos", $progress)

proc getSongTitle(muk: Muk): string =
  tryIgnore: result = muk.ctx.get_property("media-title")

proc getSongPath(muk: Muk): string =
  tryIgnore: result = muk.ctx.get_property("path")

proc seekRelative(muk: Muk, seconds = 0) =
  tryIgnore: muk.ctx.command(@["seek", $seconds, "relative", "exact"])

proc volumeRelative(muk: Muk, num = 0) =
  tryIgnore: muk.ctx.command(@["add", "volume", $num])

proc togglePause(muk: Muk) =
  tryIgnore: muk.ctx.command(@["cycle", "pause"])

proc pause(muk: Muk) =
  tryIgnore: muk.ctx.command(@["pause"])

proc getPause(muk: Muk): bool =
  tryIgnore: result = muk.ctx.get_property("pause").parseBool()

proc toggleMute(muk: Muk) =
  tryIgnore: muk.ctx.command(@["cycle", "mute"])

proc doColorSchema(tb: var TerminalBuffer) =
  tb.setBackgroundColor(bgBlack)
  tb.setForegroundColor(fgGreen)
  tb.clear(" ")

proc loadfile(muk: Muk, file: string) =
  if file == "":
    tryIgnore muk.ctx.command("stop")
  else:
    tryIgnore muk.ctx.command("loadfile", file)

proc addToPlaylist(muk: Muk, file: string) =
  tryIgnore muk.ctx.command(@["loadfile", $file, "append"])

proc addToPlaylistAndPlay(muk: Muk, file: string) =
  tryIgnore muk.ctx.command(@["loadfile", $file, "append-play"])
  ## TODO append-play does not play the file when another one is playing already...
  # tryIgnore ctx.command(@)
  # addToPlaylistAndPlay

proc nextFromPlaylist(muk: Muk) =
  tryIgnore muk.ctx.command("playlist-next")

proc prevFromPlaylist(muk: Muk) =
  tryIgnore muk.ctx.command("playlist-prev")

proc clearPlaylist(muk: Muk) =
  tryIgnore muk.ctx.command("playlist-clear")

# proc getInterpret(ctx: ptr handle): string =
#   tryIgnore ctx.command()

# proc getAlbum(ctx: ptr handle): string =
#   tryIgnore ctx.command()

# proc getSong(ctx: ptr handle): string =
#   tryIgnore ctx.command()

type
  PlaylistSong = object
    filename: string
    current: bool
    id: int

proc getPlaylist(muk: Muk): seq[PlaylistSong] =
  let js = ($muk.ctx.get_property("playlist")).parseJson()
  # echo js
  for dic in js.getElems:
    var elem = PlaylistSong()
    elem.id = dic["id"].getInt()
    elem.filename = dic["filename"].getStr()
    if dic.contains("current"):
      elem.current = dic["current"].getBool()
    else:
      elem.current = false
    result.add elem

proc log(muk: Muk, msg: string) =
  muk.infLog.text = (msg & "\n" & muk.infLog.text)
  muk.infLog.text.setLen(300)

proc fillPlaylistWidget(chooseBox: var ChooseBox, playlistSongs: seq[PlaylistSong]) =
  chooseBox.elements = @[]
  for idx, song in playlistSongs:
    chooseBox.elements.add song.filename
    if song.current:
      chooseBox.highlightIdx = idx #song.id - 1
  # chooseBox.clear()

proc infoCurrentSongDuration(muk: Muk): string =
  result = ""
  tryIgnore:
    result &= muk.ctx.get_property("time-pos")
    result &= "/"
    result &= muk.ctx.get_property("duration")

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

proc quitGui(muk: Muk) =
  muk.tb.resetAttributes()
  illwillDeinit()
  showCursor()
  echo "muk, made with ♥, mpv and Nim. Star us on github :), http://github.com/enthus1ast/muk/"
  quit(0)

proc main(): int =
  var muk = newMuk()
  ## Testing
  muk.addToPlaylist """C:\Users\david\ttt.mp4"""
  muk.addToPlaylist """C:\Users\david\Music\2016 - Nonagon Infinity\01. Robot Stop.mp3"""
  result = 1
  # var currentPath = """C:\Users\david\Music\2016 - Nonagon Infinity\"""

  # var currentPath = """D:\audio_books\Der Herr der Ringe (Hörbuch)\Der Herr der Ringe - Band 1 - Die Gefährten\"""
  # var currentPath = """D:/backup/IBC_new_2020_07_29/public/files/2019-08/"""
  # muk.fs.currentPath = currentPath
  muk.filesystemOpenDir(getCurrentDir().absolutePath())

  while true:
    let event = muk.ctx.wait_event(0)
    var key = getKey()
    var mev: MukEvent
    if muk.inPlaylist:
      mev = muk.keybindingPlaylist.toMukEvent(key)
    else:
      mev = muk.keybindingFilesystem.toMukEvent(key)

    case mev
    of MukQuitAll, MukQuitGui:
      muk.quitGui()
    of MukPauseToggle:
      muk.togglePause()
    of MukSeekForward:
      muk.seekRelative(3)
    of MukSeekBackward:
      muk.seekRelative(-3)
    of MukSeekForwardFast:
      muk.seekRelative(15)
    of MukSeekBackwardFast:
      muk.seekRelative(-15)
    of MukSwitchPane:
      muk.inPlaylist = not muk.inPlaylist
      muk.log($(muk.inPlaylist))
    of MukDebugInfo:
      muk.playlist.fillPlaylistWidget(muk.getPlaylist())
    of MukPrevFromPlaylist:
      muk.prevFromPlaylist()
    of MukNextFromPlaylist:
      muk.nextFromPlaylist()
    of MukClearPlaylist:
      # muk.clearPlaylist()
      muk.ctx.command("stop")

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
      muk.ctx.command("playlist-shuffle")
    of MukUnShuffle:
      muk.ctx.command("playlist-unshuffle")
    of MukRemoveSong:
      tryIgnore muk.ctx.command("playlist-remove", $muk.playlist.choosenIdx)
    of MukDirUp:
        muk.fs.up()
        muk.filesystem.choosenidx = 0
        muk.filesystemOpenDir(muk.fs.currentPath)
    of MukAddStuff:
      muk.addToPlaylist(muk.fs.currentPath / muk.filesystem.element())
      muk.filesystem.nextChoosenidx()
    of MukVolumeUp:
      muk.volumeRelative(20)
    of MukVolumeDown:
      muk.volumeRelative(-20)
    of MukMuteToggle:
      muk.toggleMute()
    of MukVideoToggle:
      muk.ctx.command(@["cycle", "video"])
    else:
      discard

    if key == Key.Mouse:
      let coords = getMouse()
      var ev: Events
      ev = muk.tb.dispatch(muk.progSongProgress, coords)
      if ev.contains MouseDown:
        muk.setProgressInPercent(muk.progSongProgress.valueOnPos(coords))
      ev = muk.tb.dispatch(muk.btnPlayPause, coords)
      if ev.contains MouseDown:
        # muk.ctx.setProgressInPercent(progSongProgress.valueOnPos(coords))
        muk.togglePause()

      ev = muk.tb.dispatch(muk.filesystem, coords)
      if ev.contains MouseUp:
        muk.inPlaylist = false
        muk.log(muk.filesystem.element())
        muk.addToPlaylist(muk.filesystem.element())

      ev = muk.tb.dispatch(muk.playlist, coords)
      if ev.contains MouseUp:
        muk.inPlaylist = true
        muk.log(muk.playlist.element())
        # muk.ctx.play (playlist.element())
        muk.ctx.command(@["playlist-play-index", $muk.playlist.choosenidx])



    if key == Key.Space:
      # muk.ctx.command("loadfile", """C:\Users\david\ttt.mp4""")
      # muk.ctx.command(@["playlist-play-index", "0"])
      muk.togglePause()
      # muk.ctx.loadfile(playlist.currentSong())
      discard


    if key == Key.Enter:
      # muk.ctx.command("loadfile", """C:\Users\david\Music\2016 - Nonagon Infinity\01. Robot Stop.mp3""")
      if muk.inPlaylist:
        muk.ctx.command(@["playlist-play-index", $muk.playlist.choosenidx])
      else:
        var act = muk.fs.action(muk.filesystem.element())
        muk.infSongPath.text = muk.fs.currentPath & "|" & $act #fs # filesystem.element()
        case act.kind
        of ActionKind.File:
          muk.addToPlaylistAndPlay(muk.fs.currentPath / muk.filesystem.element())
        of ActionKind.Folder:
          muk.filesystem.choosenidx = 0
          muk.filesystemOpenDir(act.folderPath)
        else:
          discard


    # poll(50)

    try:
      let mpvevent = mpv.event_name(event.event_id)
      if mpvevent != "none":
        muk.log($mpvevent)
      if mpvevent == "end-file":
        discard
        # let nextSong = playlist.next()
        # if nextSong.len != 0:
        # infLog.text = nextSong
        # muk.ctx.loadfile(nextSong)
        # else:
          # muk.ctx.command()

      # echo mpvevent
      #muk.tb.write(0, 0, $mpvevent)
      if event.event_id == mpv.EVENT_SHUTDOWN:
        break
    except:
      discard


    muk.infSongPath.text = muk.getSongTitle() & " | " & muk.getSongPath()

    muk.progSongProgress.value = muk.getProgressInPercent()
    muk.progSongProgress.text = muk.infoCurrentSongDuration()  #$ctx.getProgressInPercent()

    if muk.getPause():
      muk.btnPlayPause.text = "||"
      muk.btnPlayPause.color = fgYellow
    else:
      muk.btnPlayPause.text = ">>" # $($ctx.getPause())[0]
      muk.btnPlayPause.color = fgGreen

    muk.filesystem.title = muk.fs.currentPath
    muk.playlist.title = "Unnamed playlist (todo)"

    muk.filesystem.highlight = not muk.inPlaylist
    muk.filesystem.chooseEnabled = not muk.inPlaylist
    muk.playlist.highlight = muk.inPlaylist
    muk.playlist.chooseEnabled = muk.inPlaylist


    muk.playlist.fillPlaylistWidget(muk.getPlaylist()) # TODO not every tick...

    muk.tb.render(muk.filesystem)
    muk.tb.render(muk.playlist)
    # muk.tb.render(muk.infLog)
    muk.tb.render(muk.infSongPath)
    muk.tb.render(muk.progSongProgress)
    muk.tb.render(muk.btnPlayPause)

    muk.tb.display()
    sleep(25)
    # GC_fullCollect()

  return 0


system.quit(main())
