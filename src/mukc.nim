import messages, network, dbg, asyncnet, json
import tsonginfo, tplaylist, trepeatKind

type
  ClientStatus* = ref object
    progress*: Fanout_PROGRESS
    metadata*: Fanout_METADATA
    pause*: Fanout_PAUSE
    volume*: Fanout_VOLUME
    mute*: Fanout_MUTE
    playlist*: Fanout_PLAYLIST
    repeatKind*: RepeatKind
  Mukc* = ref object
    control*: Client
    listening*: Client
    running*: bool

## High level network controls #########################
proc setProgressInPercent*(mukc: Mukc, progress: float) {.async.} =
  var msg = newMsg Message_Client_CONTROL
  var data: Control_Client_PERCENTPOS = progress
  msg.controlKind = PERCENTPOS
  msg.data = %* data
  await mukc.control.send(msg)

proc setSeekRelative*(mukc: Mukc, seek: float) {.async.} =
  var msg = newMsg Message_Client_CONTROL
  var data: Control_Client_SEEKRELATIVE = seek
  msg.controlKind = SEEKRELATIVE
  msg.data = %* data
  await mukc.control.send(msg)

proc setPause*(mukc: Mukc, pause: bool) {.async.} =
  var msg = newMsg Message_Client_CONTROL
  var data: Control_Client_PAUSE = pause
  msg.controlKind = Control_Kind.PAUSE
  msg.data = %* data
  await mukc.control.send(msg)

proc togglePause*(mukc: Mukc) {.async.} =
  var msg = newMsg Message_Client_CONTROL
  msg.controlKind = Control_Kind.TOGGLEPAUSE
  msg.data = %* nil
  await mukc.control.send(msg)

proc loadRemoteFile*(mukc: Mukc, path: string, append: bool) {.async.} =
  var msg = newMsg Message_Client_CONTROL
  var data: Control_Client_LOADFILE = path
  if append:
    msg.controlKind = LOADFILEAPPEND
  else:
    msg.controlKind = LOADFILE
  msg.data = %* data
  await mukc.control.send(msg)

proc playlistPlayIndex*(mukc: Mukc, index: int) {.async.} =
  var msg = newMsg Message_Client_CONTROL
  msg.controlKind = PLAYINDEX
  msg.data = %* index.Control_Client_PLAYINDEX
  await mukc.control.send(msg)

proc nextFromPlaylist*(mukc: Mukc) {.async.} =
  var msg = newMsg Message_Client_CONTROL
  msg.controlKind = NEXTSONG
  msg.data = %* nil
  await mukc.control.send(msg)

proc prevFromPlaylist*(mukc: Mukc) {.async.} =
  var msg = newMsg Message_Client_CONTROL
  msg.controlKind = PREVSONG
  msg.data = %* nil
  await mukc.control.send(msg)

proc toggleMute*(mukc: Mukc) {.async.} =
  var msg = newMsg Message_Client_CONTROL
  # var data: Control_Client_TOGGLEPAUSE = nil
  msg.controlKind = Control_Kind.TOGGLEMUTE
  msg.data = %* nil
  await mukc.control.send(msg)

proc setVolumeRelative*(mukc: Mukc, volume: float) {.async.} =
  var msg = newMsg Message_Client_CONTROL
  var data: Control_Client_VOLUMERELATIV = volume
  msg.controlKind = Control_Kind.VOLUMERELATIV
  msg.data = %* data
  await mukc.control.send(msg)

proc removeSong*(mukc: Mukc, idx: int) {.async.} =
  var msg = newMsg Message_Client_CONTROL
  msg.controlKind = Control_Kind.REMOVESONG
  msg.data = %* idx.Control_Client_REMOVESONG
  await mukc.control.send(msg)

proc clearPlaylist*(mukc: Mukc) {.async.} =
  var msg = newMsg Message_Client_CONTROL
  msg.controlKind = Control_Kind.CLEARPLAYLIST
  msg.data = %* nil
  await mukc.control.send(msg)

proc cylceRepeat*(mukc: Mukc) {.async.} =
  var msg = newMsg Message_Client_CONTROL
  msg.controlKind = Control_Kind.CYCLEREPEAT
  msg.data = %* nil
  await mukc.control.send(msg)

proc quitServer*(mukc: Mukc) {.async.} =
  var msg = newMsg Message_Client_CONTROL
  msg.controlKind = Control_Kind.QUIT
  msg.data = %* nil
  await mukc.control.send(msg)

proc toggleVideo*(mukc: Mukc) {.async.} =
  var msg = newMsg Message_Client_CONTROL
  msg.controlKind = Control_Kind.TOGGLEVIDEO
  msg.data = %* nil
  await mukc.control.send(msg)

########################################################

proc newMukc*(): Mukc =
  result = Mukc()
  result.running = true
  result.control = Client() # TODO call this Remote
  result.listening = Client() # TODO call this Remote

proc connect*(mukc: Mukc, host: string, port: Port): Future[bool] {.async.} =
  ## Connect to a mukd. Returns false if connection is not possible
  try:
    mukc.control = newClient(host, await asyncnet.dial(host, port))
    mukc.listening = newClient(host, (await asyncnet.dial(host, port)))
    return true
  except:
    dbg "Could not connect to host: " & host & ":" & $port
    dbg getCurrentExceptionMsg()
    return false

proc authenticate*(mukc: Mukc, username, password: string): Future[bool] {.async.} =
  var msg = newMsg(Message_Client_Auth)
  msg.username = username
  msg.password = password
  try:
    discard await mukc.control.recv(Message_Server_AUTH)
    await mukc.control.send(msg)
    discard await mukc.control.recv(Message_GOOD)

    discard await mukc.control.recv(Message_Server_PURPOSE)
    var purpose = newMsg(Message_Client_PURPOSE)
    purpose.socketPurpose = SocketPurpose.Control
    await mukc.control.send(purpose)

    discard await mukc.listening.recv(Message_Server_AUTH)
    await mukc.listening.send(msg)
    discard await mukc.listening.recv(Message_GOOD)

    discard await mukc.listening.recv(Message_Server_PURPOSE)
    purpose = newMsg(Message_Client_PURPOSE)
    purpose.socketPurpose = SocketPurpose.Listening
    await mukc.listening.send(purpose)

    return true
  except:
    dbg "Could not authenticate"
    return false

proc recvFanout(mukc: Mukc) {.async.} =
  var st = 0
  while true:
    let msg = await mukc.listening.recv(Message_Server_Fanout)
    when isMainModule:
      echo msg
    await mukc.listening.sendGood()

proc fillFanout(cs: ClientStatus, fan: Message_Server_FANOUT) =
  ## TODO this by hand is cumbersome, write a macro that does this
  try:
    case fan.dataKind
    of FanoutDataKind.METADATA: cs.metadata = fan.data.to(Fanout_METADATA)
    of FanoutDataKind.PROGRESS: cs.progress = fan.data.to(Fanout_PROGRESS)
    of FanoutDataKind.PAUSE: cs.pause = fan.data.to(Fanout_PAUSE)
    of FanoutDataKind.VOLUME: cs.volume = fan.data.to(Fanout_VOLUME)
    of FanoutDataKind.MUTE: cs.mute = fan.data.to(Fanout_MUTE)
    of FanoutDataKind.PLAYLIST: cs.playlist = fan.data.to(Fanout_PLAYLIST)
    of FanoutDataKind.REPEATKIND: cs.repeatKind = fan.data.to(Fanout_REPEATKIND)
    else:
      discard
  except:
    discard

proc collectFanouts*(mukc: Mukc, cs: ClientStatus) {.async.} =
  ## This updates the ClientStatus with updates from the server.
  ## The client status is rendered by the `muk` terminal music player.
  while mukc.running:
    let fan = await mukc.listening.recv(Message_Server_FANOUT)
    when isMainModule:
      echo fan
    await mukc.listening.sendGood()
    cs.fillFanout(fan)

when isMainModule:
  import cligen
  var mukc = newMukc()
  var cs = ClientStatus()
  if waitFor mukc.connect("127.0.0.1", 8889.Port):
    if waitFor mukc.authenticate("foo", "baa"):
      waitFor mukc.collectFanouts(cs)