## This is the muk server part.

import net, asyncnet, asyncdispatch, json, strutils, os, tables, asyncfile,
  dbg, mpv, sets, hashes, parsecfg
import lib/[network, mpvcontrol, filesys, templates, mukdstatus]
import types/[tmessages, tsonginfo, trepeatKind, tuploadInfo, tmukd]
import auth

# from fileUpload import CHUNK_SIZE

const
  PORT = 8889.Port
  BIND_ADDR = "0.0.0.0"

proc storeDefaultMukdStatus(mukd: Mukd) =
  ## Writes the status to de filesystem.
  echo "Store mukd status."
  storeMukdStatus(mukd.getMukdStatus(), getAppDir() / "tmp/status.json")

proc applyDefaultMukdStatus(mukd: Mukd) =
  ## Writes the status to de filesystem.
  # tryIgnore:
  let status = loadMukdStatus(getAppDir() / "tmp/status.json")
  mukd.applyMukdStatus(status)
  echo "Apply mukd status."

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
  var songInfo = mukd.ctx.getMetadata().normalizeMetadata()
  songInfo.path = mukd.ctx.getSongPath()
  result.data = %* songInfo

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
proc getControl_FSLS(mukd: Mukd, forClient: Client): Message_Server_CONTROL =
  result = newMsg Message_Server_CONTROL
  result.controlKind = FSLS
  var fsls = Control_Server_FSLS()
  fsls.listing = mukd.clientFs[forClient].ls()
  fsls.currentPath = mukd.clientFs[forClient].currentPath
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

proc savePlaylist(mukd: Mukd, path: string) =
  echo "Save playlist: ", path
  var fh = open(path, fmWrite)
  for playlistSong in mukd.ctx.getPlaylist():
    fh.writeLine(playlistSong.filename)
  fh.close()

proc loadDefaultPlaylist(mukd: Mukd) =
  let defaultPlaylist = mukd.config.getSectionValue("playlist", "defaultPlaylist").absolutePath()
  echo "Load default playlist:", defaultPlaylist
  mukd.ctx.loadPlaylist(defaultPlaylist)

proc saveDefaultPlaylist(mukd: Mukd) =
  mukd.savePlaylist(
    mukd.config.getSectionValue("playlist", "defaultPlaylist")
  )

proc enumerationToSet(str: string): HashSet[string] =
  # eg: ".mp3 .ogg .opus .flac .wav" to HashSet
  result = initHashSet[string]()
  for elem in str.split(" "):
    result.incl elem

proc newMukd(): Mukd =
  result = Mukd()
  result.running = true
  result.server = newAsyncSocket()
  result.server.setSockOpt(OptReuseAddr, true)
  result.config = loadConfig(getAppDir() / "config/mukd.ini")
  result.allowedUploadExtensions = result.config.getSectionValue("upload", "allowedExtensions").enumerationToSet()
  result.users = loadUsers(getAppDir() / "config/users.db")

proc setMpvOptions(mukd: Mukd) =
  ## Forwards the [mpv] part of mukd.ini directly to libmpv
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
  # return username == "foo" and password == "baa"
  return mukd.users.valid(username, password)

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
    var answerFuture = await listeningClient.recv(Message_GOOD)

    # var answerFuture = listeningClient.recv(Message_GOOD)
    # let inTime = await withTimeout(answerFuture, 5000) ## really discard?

    # if not inTime:
    #   dbg "TIMEOUT: Listening client did not answer in time: " & listeningClient.address
    #   var error = newMsg(Message_PROTOCOLVIOLATION)
    #   error.error = "You did not respond in time, bye bye."
    #   try:
    #     await listeningClient.send(error)
    #   except:
    #     discard
      # listeningClient.kill() # TODO this must work but does not properly...
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



proc handleListening(mukd: Mukd, client: Client) {.async.} =
  dbg "Handle listening"
  mukd.listening.incl client
  await mukd.initialInformListening(client)

proc handleControl(mukd: Mukd, client: Client) {.async.} =
  dbg "Handle control"
  dbg "Create a filesystem for the controlling client"
  mukd.clientFs[client] = newFilesystem(mukd.config.getSectionValue("musicDirs", "musicDir1"))
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
      mukd.ctx.loadFile(msg.data.to(Control_Client_LOADFILE).normalizedPath().replace("\\", "/"))
      mukd.saveDefaultPlaylist()
      var fan = newMsg(Message_Server_FANOUT)
      fan = mukd.getFanout_PLAYLIST()
      await mukd.fanout(fan)
    of LOADFILEAPPEND:
      mukd.ctx.addToPlaylistAndPlay(msg.data.to(Control_Client_LOADFILEAPPEND).normalizedPath().replace("\\", "/"))
      mukd.saveDefaultPlaylist()
      var fan = newMsg(Message_Server_FANOUT)
      fan = mukd.getFanout_PLAYLIST()
      await mukd.fanout(fan)
    of ControlKind.PAUSE:
      mukd.ctx.setPause(msg.data.to(Control_Client_PAUSE))
      var fan = mukd.getFanout_PAUSE()
      await mukd.fanout(fan)
      mukd.storeDefaultMukdStatus()
    of TOGGLEPAUSE:
      discard mukd.ctx.togglePause()
      var fan = mukd.getFanout_PAUSE()
      await mukd.fanout(fan)
      fan = newMsg(Message_Server_FANOUT)
      fan.data = %* mukd.getFanout_PROGRESS()
      await mukd.fanout(fan)
      mukd.storeDefaultMukdStatus()
    of TOGGLEMUTE:
      discard mukd.ctx.toggleMute()
      var fan = mukd.getFanout_MUTE() # TODO
      await mukd.fanout(fan)
      mukd.storeDefaultMukdStatus()
    of VOLUMERELATIV:
      mukd.ctx.volumeRelative(msg.data.to(Control_Client_VOLUMERELATIV))
      var fan = mukd.getFanout_VOLUME() # TODO
      await mukd.fanout(fan)
      mukd.storeDefaultMukdStatus()
    of VOLUMEPERCENT:
      mukd.ctx.setVolume(msg.data.to(Control_Client_VOLUMEPERCENT))
      var fan = mukd.getFanout_VOLUME() # TODO
      await mukd.fanout(fan)
      mukd.storeDefaultMukdStatus()
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
      mukd.saveDefaultPlaylist()
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
      var answer = mukd.getControl_FSLS(client)
      await client.send(answer)
    of FSACTION:
      let incoming = msg.data.to(Control_Client_FSACTION)
      var act = mukd.clientFs[client].action(incoming)
      await client.send(mukd.getControl_ACTION(act))
    of FSUP:
      mukd.clientFs[client].up()
      var answer = mukd.getControl_FSLS(client)
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
    of PLAYLISTMOVE:
      let incoming = msg.data.to(Control_Client_PLAYLISTMOVE)
      mukd.ctx.playlistMove(incoming.fromIdx, incoming.toIdx)
      mukd.saveDefaultPlaylist()
      var fan = mukd.getFanout_PLAYLIST()
      await mukd.fanout(fan)
    of GOTOMUSICDIR:
      let incoming = msg.data.to(Control_Client_GOTOMUSICDIR)
      try:
        let musicDir = mukd.config.getSectionValue("musicDirs", "musicDir" & $incoming).absolutePath()
        echo musicDir
        mukd.clientFs[client].currentPath = musicDir
      except:
        echo "Music dir not found: " & "musicDir" & $incoming
        continue
    else:
      discard

proc handleUpload(mukd: Mukd, client: Client) {.async.} =
  echo "new fileupload: ", client.address
  var msg: Message_Client_UPLOAD
  try:
    msg = await client.recv(Message_Client_UPLOAD)
  except:
    dbg "could not receive Message_Client_UPLOAD"
    client.kill()
    return

  if not mukd.config.getSectionValue("upload", "uploadEnabled").parseBool():
    echo "upload is disabled"
    await client.sendBad()
    client.kill()
    return

  let path = getAppDir() / mukd.config.getSectionValue("upload", "uploadFolder") / msg.uploadInfo.name

  let maxUploadSizeByte =  mukd.config.getSectionValue("upload", "maxUploadSize").parseInt()
  if msg.uploadInfo.size > maxUploadSizeByte * 1000 * 1000:
    echo "file size is too large, incoming: ", msg.uploadInfo.size.formatSize(), " maxUploadSize:", maxUploadSizeByte.formatSize()
    await client.sendBad()
    client.kill()
    return

  if not mukd.allowedUploadExtensions.contains(path.splitFile().ext):
    echo "extension is not allowed to be uploaded: ", path.splitFile().ext
    await client.sendBad()
    client.kill()
    return

  if path.fileExists():
    echo "file exists: ", path
    await client.sendBad()
    client.kill()
    return

  await client.sendGood()
  echo "GOOD"
  echo path
  var received = 0
  var fh = openAsync(path, fmWrite)
  echo "OPENFILE"
  var chunk = newStringOfCap(CHUNK_SIZE)
  while true: # not client.socket.isClosed: # TODO this is an error case! or not received < uploadInfo.size:
    chunk = await client.socket.recv(CHUNK_SIZE)
    # echo "CHUNK: ", chunk.len
    if chunk == "": break
    await fh.write(chunk)
    received.inc chunk.len
  fh.close()

  if received != msg.uploadInfo.size:
    echo "Size do not match, got:", received, " expected:", msg.uploadInfo.size, " path: ", path
    removeFile(path)
    return

  echo "upload done: ", path
  case msg.postUploadAction
  of PostUploadAction.Nothing:
    echo "PostUploadAction.Nothing"
    discard
  of PostUploadAction.Append:
    echo "PostUploadAction.Append"
    mukd.ctx.addToPlaylist(path)

    # TODO this and the one below is copy pasta
    mukd.saveDefaultPlaylist()
    var fan = mukd.getFanout_PLAYLIST()
    await mukd.fanout fan

  of PostUploadAction.Play:
    echo "PostUploadAction.Play"
    mukd.ctx.addToPlaylistAndPlay(path)
    # TODO copy pasta
    mukd.saveDefaultPlaylist()
    var fan = mukd.getFanout_PLAYLIST()
    await mukd.fanout fan
  else: discard
  # TODO
  # - test size
  # - test checksum?
  # - Fanout download
  # client.kill()
  return


proc handleClient(mukd: Mukd, client: Client) {.async.} =
  echo "new connection: ", client.address
  try:
    if not (await mukd.handleAuth(client)):
      client.kill()
      return

    let purpose = (await mukd.askForSocketPurpose(client))
    case purpose
    of SocketPurpose.Listening:
      await mukd.handleListening(client)
    of SocketPurpose.Control:
      await mukd.handleControl(client)
    of SocketPurpose.Upload:
      await mukd.handleUpload(client)
    else:
      client.kill()

  except ClientDisconnected:
    echo "client gone..."
    mukd.listening.excl client
    if mukd.clientFs.hasKey(client):
      mukd.clientFs.del(client)
    discard

proc writeMukdStatusLoop(mukd: Mukd) {.async.} =
  ## periodically write mukd status
  while true:
    if not mukd.ctx.getPause():
      mukd.storeDefaultMukdStatus()
    await sleepAsync 5_000

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
      # echo mpvevent
      if mpvevent == "none":
        await sleepAsync(250)
        continue
      elif mpvevent == "metadata-update":
        var fan = mukd.getFanout_METADATA()
        await mukd.fanout fan
        if mukd.config.getSectionValue("", "callForSongEnable").parseBool():
          mukd.callForSong(mukd.ctx.getMetadata().normalizeMetadata())
      elif mpvevent == "tracks-changed":
        mukd.saveDefaultPlaylist()
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
  createDir(getAppDir() / mukd.config.getSectionValue("upload", "uploadFolder"))
  mukd.initMpv()
  # mukd.fs.currentPath = getCurrentDir().absolutePath()
  mukd.loadDefaultPlaylist()
  mukd.applyDefaultMukdStatus()

  asyncCheck mukd.writeMukdStatusLoop()
  asyncCheck mukd.fanoutMpvEvents()
  asyncCheck mukd.testFanout()
  waitFor mukd.serve()