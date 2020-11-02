## This is the muk server part.
import net, asyncnet, asyncdispatch, json, strutils
import dbg
import mpv
import sets
import hashes
import messages, network

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

proc authGood*(mukd: Mukd, username, password: string): bool =
  ## TODO
  return username == "foo" and password == "baa"

proc askForSocketPurpose*(mukd: Mukd, client: Client): Future[SocketPurpose] {.async.} =
  dbg "Ask client socket for purpose: ", client.address
  await client.send(newMsg Message_Server_PURPOSE)
  result = (await client.recv(Messaged_Client_PURPOSE)).socketPurpose
  dbg "Socket has the purpose: ", result

proc handleAuth(mukd: Mukd, client: Client): Future[bool] {.async.} =
  await client.send(newMsg Message_Server_AUTH)
  let msg = await client.recv(Messaged_Client_AUTH)
  echo "GOT: ", msg
  if mukd.authGood(msg.username, msg.password):
    await client.send(newMsg Message_Server_GOOD)
    return true
  else:
    await client.send(newMsg Message_Server_BAD)
    return false

proc handleListening(mukd: Mukd, client: Client) {.async.} =
  dbg "Handle listening"
  mukd.listening.incl client


proc handleControl(mukd: Mukd, client: Client) {.async.} =
  dbg "Handle control"

proc handleClient(mukd: Mukd, client: Client) {.async.} =
  echo "new connection: ", client.address
  try:
    if not (await mukd.handleAuth(client)):
      client.kill()

    let purpose = (await mukd.askForSocketPurpose(client))
    case purpose
    of Listening:
      await mukd.handleListening(client)
    of Control:
      await mukd.handleControl(client)
    else:
      client.kill()


    # while mukd.running:
    #   echo await client.recv(Messaged_Client_AUTH)
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

proc fanoutOne[T](mukd: Mukd, msg: T, listeningClient: Client) {.async.} =
  try:
    await listeningClient.send(msg)
    var answerFuture = listeningClient.recv(Messaged_Client_GOOD)
    let inTime = await withTimeout(answerFuture, 5000) ## really discard?

    if not inTime:
      dbg "Listening client did not answer in time: " & listeningClient.address
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

proc testFanout(mukd: Mukd) {.async.} =
  while true:
    await sleepAsync(5000)
    let msg = newMsg(Message_Server_GOOD)
    await mukd.fanout(msg)



when isMainModule:
  echo newMsg(Message_Server_AUTH)
  var mukd = newMukd()
  asyncCheck mukd.testFanout()
  waitFor mukd.serve()