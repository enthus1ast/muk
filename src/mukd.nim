## This is the muk server part.
import net, asyncnet, asyncdispatch, json, strutils
import dbg
import mpv
import sets
import hashes
import messages, network
import mpvcontrol
import templates

const
  PORT = 8889.Port
  BIND_ADDR = "0.0.0.0"

type
  Mukd = ref object
    server: AsyncSocket
    running: bool
    ctx: ptr handle
    listening: HashSet[Client]


proc newMukd(): Mukd =
  result = Mukd()
  result.running = true
  result.server = newAsyncSocket()
  result.server.setSockOpt(OptReuseAddr, true)

proc initMpv(mukd: Mukd) =
  mukd.ctx = mpv.create()
  if mukd.ctx.isNil:
    echo "failed creating mpv context"
    return
  # defer: mpv.terminate_destroy(mukd.ctx) # must be in muk destructor
  mukd.ctx.set_option("terminal", "no")
  mukd.ctx.set_option("video", "no")
  mukd.ctx.set_option("input-default-bindings", "yes")
  mukd.ctx.set_option("input-vo-keyboard", "no")
  mukd.ctx.set_option("osc", true)
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
    echo "FANOUT to: ", listeningClient.address
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
  for listeningClient in mukd.listening:
    asyncCheck fanoutOne(mukd, msg, listeningClient)

proc initialInformListening(mukd: Mukd, client: Client) {.async.} =
  ## Informs a newly connected client about the current status
  ## This sends all the relevant infos to bring the client gui
  ## to an informed state
  var fan = newMsg(Message_Server_FANOUT)
  tryIgnore:
    fan.data = %* {$PAUSE: mukd.ctx.getPause()}
    await mukd.fanout(fan)

  tryIgnore:
    fan = newMsg(Message_Server_FANOUT)
    fan.data = %* mukd.ctx.getMetadata().normalizeMetadata()
    await mukd.fanout(fan)

  tryIgnore:
    fan = newMsg(Message_Server_FANOUT)
    fan.data = %* {"PROGRESS": mukd.ctx.getProgressInPercent()}
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
    let msg = await client.recv(Message_Client_CONTROL)
    echo msg
    case msg.controlKind
    of LOADFILE:
      mukd.ctx.loadFile(msg.data.to(Control_Client_LOADFILE))
      var fan = newMsg(Message_Server_FANOUT)
      ## This only works after mpv has loaded the files etc, so this can only be fanouted after the mpv event
      # var songInfo: SongInfo = mukd.ctx.getMetadata().normalizeMetadata()
      # songInfo.path = mukd.ctx.getSongPath()
      # fan.data = %* songInfo # {$LOADFILE: msg.data.getStr()}

      fan.data = %* {$LOADFILE: msg.data.getStr()}
      await mukd.fanout(fan)
    of TOGGLE_PAUSE:
      # mukd.ctx.loadFile(msg.data.to(Control_Client_LOADFILE))
      let val = mukd.ctx.togglePause()
      var fan = newMsg(Message_Server_FANOUT)
      fan.data = %* {$PAUSE: val}
      await mukd.fanout(fan)

      fan = newMsg(Message_Server_FANOUT)
      fan.data = %* mukd.ctx.getProgressInPercent()
      await mukd.fanout(fan)
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

proc fanoutMpvEvents(mukd: Mukd) {.async.} =
  while mukd.running:
    try:
      let event = mukd.ctx.wait_event(0)
      let mpvevent = mpv.event_name(event.event_id)
      if mpvevent == "none":
        await sleepAsync(250)
        continue
      var msg = newMsg(Message_Server_FANOUT)
      msg.data = %* {"DEBUG": $mpvevent}
      await mukd.fanout(msg)
    except:
      discard
      # if mpvevent != "none":
      #   discard
      #   # muk.log($mpvevent)
      # if mpvevent == "end-file":
      #   discard
      # if mpvevent == "metadata-update":
      #   discard
        # let rawMetadata = muk.ctx.getMetadata()
        # muk.log($rawMetadata)
        # let songInfo = rawMetadata.normalizeMetadata()
        # muk.log(repr songInfo)
        # muk.currentSongInfo = songInfo
        # muk.currentSongInfo.path = muk.ctx.getSongPath()

import random
proc testFanout(mukd: Mukd) {.async.} =
  while mukd.running:
    await sleepAsync(500)
    # await sleepAsync(5000)
    # let msg = newMsg(Message_Server_GOOD)
    echo "."

    # let rr = rand(5).int
    if not mukd.ctx.getPause():
      var msg = newMsg(Message_Server_FANOUT)
      msg.data = %* {"PROGRESS": mukd.ctx.getProgressInPercent()}
      await mukd.fanout(msg)
    # if rr == 2:
    #   msg.data = %* @["foo", "baa", "baz"]
    # elif rr == 3:
    #   msg.data = %* "FOO"
    # elif rr == 4:
    #   msg.data = %* 123123
    # else:
    #   msg.data = %* [1,2,3,4]





when isMainModule:
  echo newMsg(Message_Server_AUTH)
  var mukd = newMukd()
  mukd.initMpv()
  asyncCheck mukd.fanoutMpvEvents()
  asyncCheck mukd.testFanout()
  waitFor mukd.serve()