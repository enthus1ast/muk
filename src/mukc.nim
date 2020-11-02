import messages, network, dbg, asyncnet, json

type
  Mukc = ref object
    control: Client
    listening: Client

proc newMukc(): Mukc =
  result = Mukc()
  # result.control = Client # TODO call this Remote
  # result.listening = Client # TODO call this Remote

proc connect(mukc: Mukc, host: string, port: Port): Future[bool] {.async.} =
  try:
    mukc.control = newClient(host, await asyncnet.dial(host, port))
    mukc.listening = newClient(host, (await asyncnet.dial(host, port)))
    return true
  except:
    dbg "Could not connect to host: " & host & ":" & $port
    dbg getCurrentExceptionMsg()
    return false

proc authenticate(mukc: Mukc, username, password: string): Future[bool] {.async.} =
  # let msg = newMsg(Message_Client_Auth(username: username, password: password))
  var msg = newMsg(Message_Client_Auth)
  msg.username = username
  msg.password = password
  try:
    discard await mukc.control.recv(Message_Server_AUTH)
    await mukc.control.send(msg)
    discard await mukc.control.recv(Message_Server_GOOD)
    var purpose = newMsg(Message_Client_PURPOSE)
    purpose.socketPurpose = SocketPurpose.Control
    await mukc.control.send(purpose)


    discard await mukc.listening.recv(Message_Server_AUTH)
    await mukc.listening.send(msg)
    discard await mukc.listening.recv(Message_Server_GOOD)
    purpose = newMsg(Message_Client_PURPOSE)
    purpose.socketPurpose = SocketPurpose.Listening
    await mukc.listening.send(purpose)


    return true
  except:
    dbg "Could not authenticate "
    return false


when isMainModule:
  var mukc = newMukc()
  echo waitFor mukc.connect("127.0.0.1", 8889.Port)
  echo waitFor mukc.authenticate("foo", "baa")