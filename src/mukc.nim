import messages, network, dbg, asyncnet, json

type
  Mukc = ref object
    control: Client
    listening: Client

proc newMukc(): Mukc =
  result = Mukc()
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

proc authenticate(mukc: Mukc, username, password: string): Future[bool] {.async.} =
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
    echo msg
    # st.inc 4500
    # echo st
    # await sleepAsync st

    await mukc.listening.sendGood()


when isMainModule:
  var mukc = newMukc()
  if waitFor mukc.connect("127.0.0.1", 8889.Port):
    if waitFor mukc.authenticate("foo", "baa"):
      waitFor mukc.recvFanout()
