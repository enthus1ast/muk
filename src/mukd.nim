## This is the muk server part.
import net, asyncnet, asyncdispatch, json, strutils, os, tables
import dbg
import mpv
import sets
import hashes
import messages, network
import mpvcontrol
import templates
import parsecfg
import filesys

import tsonginfo, trepeatKind
import tmukd

const
  PORT = 8889.Port
  BIND_ADDR = "0.0.0.0"


### High level mpv control #############################################

proc getFanout_PROGRESS(mukd: Mukd): Message_Server_FANOUT =
  result = newMsg(Message_Server_FANOUT)
  result.dataKind = FanoutDataKind.PROGRESS
  var data = Fanout_PROGRESS()
  data.percent = mukd.ctx.getProgressInPercent()
  data.timePos = mukd.ctx.getTimePos()
  data.duration = mukd.ctx.getDuration()
  result.data = %* data

proc getFanout_METADATA(mukd: Mukd): Message_Server_FANOUT =
  result = newMsg(Message_Server_FANOUT)
  result.dataKind = FanoutDataKind.METADATA
  result.data = %* mukd.ctx.getMetadata().normalizeMetadata()

proc getFanout_PAUSE(mukd: Mukd): Message_Server_FANOUT =
  result = newMsg(Message_Server_FANOUT)
  result.dataKind = FanoutDataKind.PAUSE
  result.data = %* mukd.ctx.getPause().Fanout_PAUSE

proc getFanout_MUTE(mukd: Mukd): Message_Server_FANOUT =
  result = newMsg(Message_Server_FANOUT)
  result.dataKind = FanoutDataKind.MUTE
  result.data = %* mukd.ctx.getMute().Fanout_MUTE

proc getFanout_VOLUME(mukd: Mukd): Message_Server_FANOUT =
  result = newMsg(Message_Server_FANOUT)
  result.dataKind = FanoutDataKind.VOLUME
  result.data = %* mukd.ctx.getVolume().Fanout_VOLUME

proc getFanout_PLAYLIST(mukd: Mukd): Message_Server_FANOUT =
  result = newMsg(Message_Server_FANOUT)
  result.dataKind = FanoutDataKind.PLAYLIST
  result.data = %* mukd.ctx.getPlaylist().Fanout_PLAYLIST

proc getFanout_REPEATKIND(mukd: Mukd): Message_Server_FANOUT =
  result = newMsg(Message_Server_FANOUT)
  result.dataKind = FanoutDataKind.REPEATKIND
  result.data = %* mukd.repeatKind

# -----------------------------------------------------------------------
proc getControl_FSLS(mukd: Mukd): Message_Server_CONTROL =
  result = newMsg Message_Server_CONTROL
  result.controlKind = FSLS
  var fsls = Control_Server_FSLS()
  fsls.listing = mukd.fs.ls()
  fsls.currentPath = mukd.fs.currentPath
  result.data = %* fsls

proc getControl_ACTION(mukd: Mukd, act: Action): Message_Server_CONTROL =
  ## To inform the client about an action # TODO maybe send wich action
  result = newMsg Message_Server_CONTROL
  result.controlKind = FSACTION
  result.data = %* act

proc setRepeatKind(mukd: Mukd, repeatKind: RepeatKind) =
  case repeatKind
  of RepeatKind.None:
    mukd.ctx.loopFile(false)
    mukd.ctx.loopPlaylist(false)
  of RepeatKind.Song:
    mukd.ctx.loopFile(true)
    mukd.ctx.loopPlaylist(false)
  of RepeatKind.List:
    mukd.ctx.loopFile(false)
    mukd.ctx.loopPlaylist(true)

#########################################################################


proc newMukd(): Mukd =
  result = Mukd()
  result.running = true
  result.server = newAsyncSocket()
  result.server.setSockOpt(OptReuseAddr, true)
  result.config = loadConfig(getAppDir() / "mukd.ini")
  result.fs = newFilesystem()

proc setMpvOptions(mukd: Mukd) =
  echo "Forwarding mpv settings:"
  for key, val in mukd.config["mpv"]:
    echo "set: ", key, " = ", val
    mukd.ctx.set_option(key, val)

proc initMpv(mukd: Mukd) =
  mukd.ctx = mpv.create()
  if mukd.ctx.isNil:
    echo "failed creating mpv context"
    return
  # defer: mpv.terminate_destroy(mukd.ctx) # must be in muk destructor
  mukd.ctx.set_option("terminal", "no")
  mukd.ctx.set_option("video", "no")
  mukd.setMpvOptions()
  check_error mukd.ctx.initialize()

proc authGood*(mukd: Mukd, username, password: string): bool =
  ## TODO
  return username == "foo" and password == "baa"

proc askForSocketPurpose*(mukd: Mukd, client: Client): Future[SocketPurpose] {.async.} =
  dbg "Ask client socket for purpose: ", client.address
  await client.send(newMsg Message_Server_PURPOSE)
  result = (await client.recv(Message_Client_PURPOSE)).socketPurpose
  dbg "Socket has the purpose: ", result

proc handleAuth(mukd: Mukd, client: Client): Future[bool] {.async.} =
  await client.send(newMsg Message_Server_AUTH)
  let msg = await client.recv(Message_Client_AUTH)
  echo "GOT: ", msg
  if mukd.authGood(msg.username, msg.password):
    await client.sendGood()
    return true
  else:
    await client.sendBad()
    return false

proc fanoutOne[T](mukd: Mukd, msg: T, listeningClient: Client) {.async.} =
  try:
    # echo "FANOUT to: ", listeningClient.address
    await listeningClient.send(msg)
    var answerFuture = listeningClient.recv(Message_GOOD)
    let inTime = await withTimeout(answerFuture, 5000) ## really discard?

    if not inTime:
      dbg "TIMEOUT: Listening client did not answer in time: " & listeningClient.address
      var error = newMsg(Message_PROTOCOLVIOLATION)
      error.error = "You did not respond in time, bye bye."
      try:
        await listeningClient.send(error)
      except:
        discard
      listeningClient.kill()
  except:
    dbg "could not fanout to: ", listeningClient.address
    try: # TODO fix this ugly
      mukd.listening.excl listeningClient
      listeningClient.kill()
    except:
      dbg "client gone.. in fanout: ", listeningClient.address

proc fanout[T](mukd: Mukd, msg: T) {.async.} =
  var msgcopy = msg
  var idx = 0
  for listeningClient in mukd.listening:
    msgcopy.fid = idx
    idx.inc
    asyncCheck fanoutOne(mukd, msgcopy, listeningClient)

proc initialInformListening(mukd: Mukd, client: Client) {.async.} =
  ## Informs a newly connected client about the current status
  ## This sends all the relevant infos to bring the client gui
  ## to an informed state
  var fan: Message_Server_FANOUT
  tryIgnore:
    fan = mukd.getFanout_PAUSE
    await mukd.fanout(fan)

  tryIgnore:
    # fan = newMsg(Message_Server_FANOUT)
    # fan.data = %* mukd.ctx.getMetadata().normalizeMetadata()
    fan = mukd.getFanout_METADATA()
    await mukd.fanout(fan)

  tryIgnore:
    fan = mukd.getFanout_PROGRESS()
    await mukd.fanout(fan)

  tryIgnore:
    fan = mukd.getFanout_VOLUME()
    await mukd.fanout(fan)

  tryIgnore:
    fan = mukd.getFanout_MUTE()
    await mukd.fanout(fan)

  tryIgnore:
    fan = mukd.getFanout_PLAYLIST()
    await mukd.fanout(fan)

  tryIgnore:
    fan = mukd.getFanout_REPEATKIND()
    await mukd.fanout(fan)



#  tryIgnore:
#     fan = newMsg(Message_Server_FANOUT)
#     fan.data = %* mukd.ctx.()
#     await mukd.fanout(fan)




proc handleListening(mukd: Mukd, client: Client) {.async.} =
  dbg "Handle listening"
  mukd.listening.incl client
  await mukd.initialInformListening(client)

proc handleControl(mukd: Mukd, client: Client) {.async.} =
  dbg "Handle control"
  while mukd.running:

    var msg: Message_Client_CONTROL
    try:
      msg = await client.recv(Message_Client_CONTROL)
    except:
      dbg "could not receive Message_Client_CONTROL"
      client.kill()
      return
    echo msg
    case msg.controlKind
    of PERCENTPOS:
      mukd.ctx.setProgressInPercent(msg.data.to(Control_Client_PERCENTPOS))
      var fan = mukd.getFanout_PROGRESS()
      await mukd.fanout(fan)
    of SEEKRELATIVE:
      mukd.ctx.seekRelative(msg.data.to(Control_Client_SEEKRELATIVE))
      var fan = mukd.getFanout_PROGRESS()
      await mukd.fanout(fan)
    of LOADFILE:
      mukd.ctx.loadFile(msg.data.to(Control_Client_LOADFILE).normalizedPath())
      var fan = newMsg(Message_Server_FANOUT)
      ## This only works after mpv has loaded the files etc, so this can only be fanouted after the mpv event
      # var songInfo: SongInfo = mukd.ctx.getMetadata().normalizeMetadata()
      # songInfo.path = mukd.ctx.getSongPath()
      # fan.data = %* songInfo # {$LOADFILE: msg.data.getStr()}
      # fan.data = %* {$LOADFILE: msg.data.getStr()}
      fan = mukd.getFanout_PLAYLIST()
      await mukd.fanout(fan)
    of LOADFILEAPPEND:
      mukd.ctx.addToPlaylistAndPlay(msg.data.to(Control_Client_LOADFILEAPPEND).normalizedPath())
      var fan = newMsg(Message_Server_FANOUT)
      fan = mukd.getFanout_PLAYLIST()
      await mukd.fanout(fan)
    of ControlKind.PAUSE:
      mukd.ctx.setPause(msg.data.to(Control_Client_PAUSE))
      var fan = mukd.getFanout_PAUSE()
      await mukd.fanout(fan)
    of TOGGLEPAUSE:
      # mukd.ctx.loadFile(msg.data.to(Control_Client_LOADFILE))
      discard mukd.ctx.togglePause()
      var fan = mukd.getFanout_PAUSE()
      await mukd.fanout(fan)
      fan = newMsg(Message_Server_FANOUT)
      fan.data = %* mukd.getFanout_PROGRESS()
      await mukd.fanout(fan)
    of TOGGLEMUTE:
      # mukd.ctx.loadFile(msg.data.to(Control_Client_LOADFILE))
      discard mukd.ctx.toggleMute()
      var fan = mukd.getFanout_MUTE() # TODO
      await mukd.fanout(fan)
      # fan = newMsg(Message_Server_FANOUT)
      # fan.data = %* mukd.ctx.getProgressInPercent()
      # await mukd.fanout(fan)
    of VOLUMERELATIV:
      mukd.ctx.volumeRelative(msg.data.to(Control_Client_VOLUMERELATIV))
      var fan = mukd.getFanout_VOLUME() # TODO
      await mukd.fanout(fan)
    of PLAYINDEX:
      mukd.ctx.playlistPlayIndex(msg.data.to(Control_Client_PLAYINDEX))
    of NEXTSONG:
      mukd.ctx.nextFromPlaylist()
    of PREVSONG:
      mukd.ctx.prevFromPlaylist()
    of REMOVESONG:
      mukd.ctx.removeSong(msg.data.to(Control_Client_REMOVESONG))
      var fan = mukd.getFanout_PLAYLIST()
      await mukd.fanout(fan)
    of CLEARPLAYLIST:
      mukd.ctx.clearPlaylist()
      var fan = mukd.getFanout_PLAYLIST()
      await mukd.fanout(fan)
    of CYCLEREPEAT:
      mukd.repeatKind = mukd.repeatKind.cycleRepeatKind()
      mukd.setRepeatKind(mukd.repeatKind)
      var fan = mukd.getFanout_REPEATKIND()
      await mukd.fanout(fan)
    # of SETREPEAT: # TODO
    #   mukd.repeatKind = msg.data.to(Control_Client_SETREPEAT)
    #   mukd.setRepeatKind(mukd.repeatKind)
    #   var fan = mukd.getFanout_REPEATKIND()
    #   await mukd.fanout(fan)
    of QUIT:
      if mukd.config.getSectionValue("", "clientCanQuitServer").parseBool():
        quit()
    of TOGGLEVIDEO:
      if mukd.config.getSectionValue("video", "videoEnabled").parseBool():
        mukd.ctx.toggleVideo()
    of FSLS:
      var answer = mukd.getControl_FSLS()
      await client.send(answer)
    of FSACTION:
      let incoming = msg.data.to(Control_Client_FSACTION)
      var act = mukd.fs.action(incoming)
      await client.send(mukd.getControl_ACTION(act))
      # case act.kind
      # of ActionKind.File:
      #   discard
      #   mukd.ctx.addToPlaylistAndPlay(mukd.fs.currentPath /  incoming )
      #   var answer = mukd.getControl_ACTION()
      #   await client.send(answer)
      # of ActionKind.Folder:
      #   var answer = mukd.getControl_FSLS()
      #   await client.send(answer)
      # else:
      #   var answer = mukd.getControl_ACTION()
      #   await client.send(answer)
    of FSUP:
      mukd.fs.up()
      var answer = mukd.getControl_FSLS()
      await client.send(answer)
    # of FSCD:
    #   discard
      # let incoming = msg.data.to(Control_Client_FSCD)
      # mukd.fs.cd(incoming)
      # var answer = newMsg Message_Server_CONTROL
      # answer.controlKind = FSLS
      # answer.data = %* mukd.fs.ls().Control_Server_FSLS
      # # await client.send(answer)
      # # answer.controlKind = FSLS
      # await client.send(answer)


    else:
      discard

proc handleClient(mukd: Mukd, client: Client) {.async.} =
  echo "new connection: ", client.address
  try:
    if not (await mukd.handleAuth(client)):
      client.kill()

    let purpose = (await mukd.askForSocketPurpose(client))
    case purpose
    of SocketPurpose.Listening:
      await mukd.handleListening(client)
    of SocketPurpose.Control:
      await mukd.handleControl(client)
    else:
      client.kill()

  except ClientDisconnected:
    echo "client gone..."
    mukd.listening.excl client
    discard

proc serve(mukd: Mukd) {.async.} =
  mukd.server.bindAddr(PORT, BIND_ADDR)
  mukd.server.listen()
  echo "mukd listens on port: ", $PORT
  while mukd.running:
    var (address, socket) = await mukd.server.acceptAddr()
    var client = newClient(address, socket)
    asyncCheck mukd.handleClient(client)

proc callForSong(mukd: Mukd, metadata: SongInfo) =
  ## Calls the binary specified in "callForSong"
  tryIgnore:
    let cmdRaw = mukd.config.getSectionValue("", "callForSong")
    let cmd = cmdRaw % [
      "artist", metadata.artist,
      "title", metadata.title,
      "album", metadata.album,
      "path", metadata.path
    ]
    echo cmd
    discard execShellCmd(cmd)

proc fanoutMpvEvents(mukd: Mukd) {.async.} =
  while mukd.running:
    try:
      let event = mukd.ctx.wait_event(0)
      let mpvevent = mpv.event_name(event.event_id)
      echo mpvevent
      if mpvevent == "none":
        await sleepAsync(250)
        continue
      elif mpvevent == "metadata-update":
        var fan = mukd.getFanout_METADATA()
        await mukd.fanout fan
        if mukd.config.getSectionValue("", "callForSongEnable").parseBool():
          mukd.callForSong(mukd.ctx.getMetadata().normalizeMetadata())
      elif mpvevent == "tracks-changed":
        var fan = mukd.getFanout_PLAYLIST()
        await mukd.fanout fan
      elif mpvevent == "shutdown":
        quit() ## find a way to capture the click on "x" and just close video window
      var msg = newMsg(Message_Server_FANOUT)
      msg.data = %* {"DEBUG": $mpvevent}
      await mukd.fanout(msg)
    except:
      discard

import random
proc testFanout(mukd: Mukd) {.async.} =
  while mukd.running:
    await sleepAsync(500)
    # echo "."

    if not mukd.ctx.getPause():
      var msg = mukd.getFanout_PROGRESS()
      await mukd.fanout(msg)

when isMainModule:
  echo newMsg(Message_Server_AUTH)
  var mukd = newMukd()
  mukd.initMpv()

  mukd.fs.currentPath = getCurrentDir().absolutePath()


  asyncCheck mukd.fanoutMpvEvents()
  asyncCheck mukd.testFanout()
  waitFor mukd.serve()