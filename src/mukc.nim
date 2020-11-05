import messages, network, dbg, asyncnet, json
import tsonginfo

type
  # ChangeCb = proc ()
  ClientStatus* = ref object
    progress*: Fanout_PROGRESS
    metadata*: Fanout_METADATA
    pause*: Fanout_PAUSE
  Mukc* = ref object
    control*: Client
    listening*: Client
    running*: bool

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
    # if not mukc.control.socket.isClosed: mukc.control.socket.close()
    # if not mukc.listening.socket.isClosed: mukc.listening.socket.close()
    return false

proc authenticate*(mukc: Mukc, username, password: string): Future[bool] {.async.} =
  # let msg = newMsg(Message_Client_Auth(username: username, password: password))
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

# proc recvFanout(mukc: Mukc): Future[JsonNode] {.async.} =
proc recvFanout(mukc: Mukc) {.async.} =
  var st = 0
  while true:
    # let line = await mukc.listening.socket.recvLine()
    # echo "l: ", line
    # let js = parseJson(line)
    # echo "j: ", js
    # echo "FANOUT:", parseJson(await mukc.listening.socket.recvLine())
    let msg = await mukc.listening.recv(Message_Server_Fanout)
    when isMainModule:
      echo msg
    # st.inc 4500
    # echo st
    # await sleepAsync st
    await mukc.listening.sendGood()

proc fillFanout(cs: ClientStatus, fan: Message_Server_FANOUT) =
  ## TODO this by hand is cumbersome, write a macro that does this
  try:
    case fan.dataKind
    of FanoutDataKind.METADATA: cs.metadata = fan.data.to(Fanout_METADATA)
    of FanoutDataKind.PROGRESS: cs.progress = fan.data.to(Fanout_PROGRESS)
    of FanoutDataKind.PAUSE: cs.pause = fan.data.to(Fanout_PAUSE)
    else:
      discard
  except:
    discard
  # echo repr cs

# proc collectFanouts(mukc: Mukc, cs: ClientStatus, changeCb: ChangeCb) {.async.} =
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

  # proc dumpListening():

  var mukc = newMukc()
  var cs = ClientStatus()
  if waitFor mukc.connect("127.0.0.1", 8889.Port):
    if waitFor mukc.authenticate("foo", "baa"):
      waitFor mukc.collectFanouts(cs)
      # waitFor mukc.recvFanout()
