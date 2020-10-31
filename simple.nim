## https://github.com/mpv-player/mpv/blob/master/etc/input.conf

import os
import mpv
import asyncdispatch
import illwill
import illwillWidgets
import strutils
import filesystem as filesystemModule
# import playlist as pl

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

proc getProgressInPercent(ctx: ptr handle): float =
  result = 0.0
  tryIgnore: result = (parseFloat ctx.get_property("percent-pos")).clamp(0.0, 100.0)

proc setProgressInPercent(ctx: ptr handle, progress: float) =
  tryIgnore: ctx.set_property("percent-pos", $progress)

proc getSongTitle(ctx: ptr handle): string =
  tryIgnore: result = ctx.get_property("media-title")

proc getSongPath(ctx: ptr handle): string =
  tryIgnore: result = ctx.get_property("path")

proc seekRelative(ctx: ptr handle, seconds = 0) =
  tryIgnore: ctx.command(@["seek", $seconds, "relative", "exact"])

proc volumeRelative(ctx: ptr handle, num = 0) =
  tryIgnore: ctx.command(@["add", "volume", $num])

proc togglePause(ctx: ptr handle) =
  tryIgnore: ctx.command(@["cycle", "pause"])

proc pause(ctx: ptr handle) =
  tryIgnore: ctx.command(@["pause"])

proc getPause(ctx: ptr handle): bool =
  tryIgnore: result = ctx.get_property("pause").parseBool()

proc toggleMute(ctx: ptr handle) =
  tryIgnore: ctx.command(@["cycle", "mute"])

proc doColorSchema(tb: var TerminalBuffer) =
  tb.setBackgroundColor(bgBlack)
  tb.setForegroundColor(fgGreen)
  tb.clear(" ")

proc loadfile(ctx: ptr handle, file: string) =
  if file == "":
    tryIgnore ctx.command("stop")
  else:
    tryIgnore ctx.command("loadfile", file)

proc addToPlaylist(ctx: ptr handle, file: string) =
  tryIgnore ctx.command(@["loadfile", $file, "append"])

proc addToPlaylistAndPlay(ctx: ptr handle, file: string) =
  tryIgnore ctx.command(@["loadfile", $file, "append-play"])
  ## TODO append-play does not play the file when another one is playing already...
  # tryIgnore ctx.command(@)
  # addToPlaylistAndPlay

proc nextFromPlaylist(ctx: ptr handle) =
  tryIgnore ctx.command("playlist-next")

proc prevFromPlaylist(ctx: ptr handle) =
  tryIgnore ctx.command("playlist-prev")

proc clearPlaylist(ctx: ptr handle) =
  tryIgnore ctx.command("playlist-clear")
# var orgBg = getBackgroundColor()
# var odgFg = ter

import json
type
  PlaylistSong = object
    filename: string
    current: bool
    id: int

proc getPlaylist(ctx: ptr handle): seq[PlaylistSong] =
  let js = ($ctx.get_property("playlist")).parseJson()
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

### Filesystem stuff
# import os



# var playlist = newPlaylist()

# var currentFile = ""
var inPlaylist = false

# Widgets

var filesystem = newChooseBox(@[], 1, 1, terminalWidth() div 2, terminalHeight() - 5, color = fgGreen )
var playlist = newChooseBox(@[],  terminalWidth() div 2, 1, terminalWidth() div 2, terminalHeight() - 5 , color = fgGreen)

var infLog = newInfoBox("logbox", terminalWidth() div 2, 1, terminalWidth() div 3, 10)
var infSongPath = newInfoBox("", 0, terminalHeight() - 2, terminalWidth(), 1)
var progSongProgress = newProgressBar(   "", 2, terminalHeight() - 1, terminalWidth() - 2, 0.0, 100.0, bgTodo = bgBlack)
progSongProgress.color = fgWhite
progSongProgress.colorText = fgRed

var btnPlayPause = newButton(">", 0, terminalHeight() - 1, 2, 1, false)

proc log(msg: string) =
  infLog.text = (msg & "\n" & infLog.text)
  infLog.text.setLen(300)

proc fillPlaylistWidget(chooseBox: var ChooseBox, playlistSongs: seq[PlaylistSong]) =
  chooseBox.elements = @[]
  for idx, song in playlistSongs:
    chooseBox.elements.add song.filename
    if song.current:
      chooseBox.highlightIdx = idx #song.id - 1

proc infoCurrentSongDuration(ctx: ptr handle): string =
  result = ""
  tryIgnore:
    result &= ctx.get_property("time-pos")
    result &= "/"
    result &= ctx.get_property("duration")

proc fillFilesystem(filesystem: var ChooseBox, elems: seq[string]) =
  # TODO test if this is neccasary
  filesystem.elements.setLen(0)
  for elem in elems:
    filesystem.elements.add elem
# proc addSelectedItemToPlaylist

import sequtils

var fs = newFilesystem()

proc main(): int =
  result = 1
  var currentPath = """C:\Users\david\Music\2016 - Nonagon Infinity\"""
  # var currentPath = """D:\audio_books\Der Herr der Ringe (Hörbuch)\Der Herr der Ringe - Band 1 - Die Gefährten\"""
  # var currentPath = """D:/backup/IBC_new_2020_07_29/public/files/2019-08/"""
  fs.currentPath = currentPath
  filesystem.fillFilesystem(fs.ls)
  # filesystem.add ".."
  # for file in walkFiles(currentPath / """*""" ):
  #   # echo file
  #   filesystem.add file

  # if paramCount() != 1:
  #   echo "pass a single media file as argument"
  #   return

  let ctx = mpv.create()
  if ctx.isNil:
    echo "failed creating mpv context"
    return
  defer: mpv.terminate_destroy(ctx)

  # Enable default key bindings, so the user can actually interact with
  # the player (and e.g. close the window).
  # ctx.set_option("terminal", "yes")
  # ctx.set_option("input-default-bindings", "yes")
  # ctx.set_option("input-vo-keyboard", "yes")
  # ctx.set_option("osc", true)

  ctx.set_option("terminal", "no")
  ctx.set_option("video", "no")
  ctx.set_option("input-default-bindings", "yes")
  ctx.set_option("input-vo-keyboard", "no")
  ctx.set_option("osc", true)
  # ctx.set_option("osc", true)

  #ctx.set_option("really-quiet", "yes")

  # Done setting up options.
  check_error ctx.initialize()

  ## Testing
  ctx.addToPlaylist """C:\Users\david\ttt.mp4"""
  ctx.addToPlaylist """C:\Users\david\Music\2016 - Nonagon Infinity\01. Robot Stop.mp3"""

  echo ctx.getPlaylist()
  # if true:
  #   quit()

  # Play this file.
  # ctx.command("loadfile", paramStr(1))

  asyncCheck foo()

  setControlCHook(exitProc)
  illwillInit(fullScreen = true, mouse = true)
  hideCursor()

  var tb = newTerminalBuffer(terminalWidth(), terminalHeight())


  # tb.doColorSchema()
  # while true:
  #   var key = getKey()
  #   if key == Key.Mouse:
  #     echo getMouse()
  #   tb.display()
  #   sleep(10)

  while true:

    # var title: string
    # tb.write(0, 0, $ctx.getProgressInPercent())
    # tb.write(0, 1, $ctx.getSongTitle())
    # tb.write(0, 2, $ctx.getSongPath())

    let event = ctx.wait_event(0)
    # ctx.command()
    var key = getKey()
    if key == Key.P:
      ctx.togglePause()

    ## Seeking
    # Slow
    if key == Key.Right or key == Key.L:
      ctx.seekRelative(3)
    if key == Key.Left or key == Key.H:
      ctx.seekRelative(-3)

    # Fast
    if key == Key.ShiftL:
      ctx.seekRelative(15)
    if key == Key.ShiftH:
      ctx.seekRelative(-15)

    ## Windows
    if key == Key.Tab:
      inPlaylist = not inPlaylist
      log($inPlaylist)

    if key == Key.I:
      # ctx.command("query", "${playlist}")
      # log(ctx.get_property("playlist"))
      # log($ctx.getPlaylist())
      playlist.fillPlaylistWidget(ctx.getPlaylist())

    ## Playlist
    if key == Key.ShiftK:
      ctx.prevFromPlaylist()
    if key == Key.ShiftJ:
      ctx.nextFromPlaylist()
    if key == Key.C:
      # ctx.clearPlaylist()
      ctx.command("stop")

    if inPlaylist:
      if key == Key.J or key == Key.Down:
        playlist.nextChoosenidx()
      if key == Key.K or key == Key.Up:
        playlist.prevChoosenidx()
      if key == Key.S:
        ctx.command("playlist-shuffle")
      if key == Key.ShiftS:
        ctx.command("playlist-unshuffle")
      if key == Key.D:
        tryIgnore ctx.command("playlist-remove", $playlist.choosenIdx)
    else:
      if key == Key.Colon:
        fs.up()
        filesystem.choosenidx = 0
        filesystem.fillFilesystem(fs.ls())
      if key == Key.J or key == Key.Down:
        filesystem.nextChoosenidx()
      if key == Key.K or key == Key.Up:
        filesystem.prevChoosenidx()
      if key == Key.A:
        # filesystem.choosenidx -= 1
        ctx.addToPlaylist filesystem.element()
        filesystem.nextChoosenidx()


    ## Volume
    if key == Key.Plus:
      ctx.volumeRelative(20)
    if key == Key.Minus:
      ctx.volumeRelative(-20)
    if key == Key.M:
      ctx.toggleMute()

    ## Show video
    if key == Key.V:
      ctx.command(@["cycle", "video"])

    if key == Key.Mouse:
      let coords = getMouse()
      var ev: Events
      ev = tb.dispatch(progSongProgress, coords)
      if ev.contains MouseDown:
        ctx.setProgressInPercent(progSongProgress.valueOnPos(coords))
      ev = tb.dispatch(btnPlayPause, coords)
      if ev.contains MouseDown:
        # ctx.setProgressInPercent(progSongProgress.valueOnPos(coords))
        ctx.togglePause()

      ev = tb.dispatch(filesystem, coords)
      if ev.contains MouseUp:
        inPlaylist = false
        log(filesystem.element())
        ctx.addToPlaylist(filesystem.element())

      ev = tb.dispatch(playlist, coords)
      if ev.contains MouseUp:
        inPlaylist = true
        log(playlist.element())
        # ctx.play (playlist.element())
        ctx.command(@["playlist-play-index", $playlist.choosenidx])



    if key == Key.Space:
      # ctx.command("loadfile", """C:\Users\david\ttt.mp4""")
      # ctx.command(@["playlist-play-index", "0"])
      ctx.togglePause()
      # ctx.loadfile(playlist.currentSong())
      discard


    if key == Key.Enter:
      # ctx.command("loadfile", """C:\Users\david\Music\2016 - Nonagon Infinity\01. Robot Stop.mp3""")
      if inPlaylist:
        ctx.command(@["playlist-play-index", $playlist.choosenidx])
      else:
        var act = fs.action(filesystem.element())
        infSongPath.text = fs.currentPath & "|" & $act #fs # filesystem.element()
        case act.kind
        of ActionKind.File:
          ctx.addToPlaylistAndPlay(filesystem.element())
        of ActionKind.Folder:
          filesystem.choosenidx = 0
          filesystem.fillFilesystem(act.folderContent)
        else:
          discard


    # poll(50)

    try:
      let mpvevent = mpv.event_name(event.event_id)
      if mpvevent != "none":
        log($mpvevent)
      if mpvevent == "end-file":
        discard
        # let nextSong = playlist.next()
        # if nextSong.len != 0:
        # infLog.text = nextSong
        # ctx.loadfile(nextSong)
        # else:
          # ctx.command()

      # echo mpvevent
      #tb.write(0, 0, $mpvevent)
      if event.event_id == mpv.EVENT_SHUTDOWN:
        break
    except:
      discard


    infSongPath.text = ctx.getSongTitle() & " | " & ctx.getSongPath()

    progSongProgress.value = ctx.getProgressInPercent()
    progSongProgress.text = ctx.infoCurrentSongDuration()  #$ctx.getProgressInPercent()

    if ctx.getPause():
      btnPlayPause.text = "||"
    else:
      btnPlayPause.text = ">>" # $($ctx.getPause())[0]


    filesystem.highlight = not inPlaylist
    filesystem.chooseEnabled = not inPlaylist
    playlist.highlight = inPlaylist
    playlist.chooseEnabled = inPlaylist


    playlist.fillPlaylistWidget(ctx.getPlaylist()) # TODO not every tick...

    tb.render(filesystem)
    tb.render(playlist)
    # tb.render(infLog)
    tb.render(infSongPath)
    tb.render(progSongProgress)
    tb.render(btnPlayPause)

    tb.display()
    sleep(25)
    # GC_fullCollect()

  return 0


system.quit(main())
