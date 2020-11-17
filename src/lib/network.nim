import json, asyncdispatch, asyncnet, net, strutils, hashes, dbg
import ../types/tmessages

export asyncdispatch
export asyncnet
export net

type
  ClientDisconnected* = Exception
  Client* = ref object
    address*: string
    socket*: AsyncSocket
    peerAddr: (string, Port)
    localAddr: (string, Port)

proc kill*(client: Client) =
  if not client.socket.isClosed:
    try:
      client.socket.close()
    except:
      discard
  raise newException(ClientDisconnected, client.address)

proc hash*(client: Client): Hash =
  result = 0
  result = result !& client.address.hash()
  result = result !& hash(client.peerAddr)
  result = result !& hash(client.localAddr)

proc newClient*(address: string, socket: AsyncSocket): Client =
  result = Client(address: address, socket: socket)
  # result.peerAddr = socket.getPeerAddr() # need this for hashing, socket could be gone when we want to remove
  result.localAddr = socket.getLocalAddr() # need this for hashing, socket could be gone when we want to remove


proc newMsg*[T](msg: typedesc[T]): T =
  const kindName = ($T).split("_")[^1]
  result = T()
  result.kind = parseEnum[MessageTypes](kindName)

proc send*[T](client: Client, msg: T): Future[void] {.async.} =
  try:
    await client.socket.send($ %* msg & "\n")
  except:
    dbg "Could not send to client:" & getCurrentExceptionMsg()
    client.kill()
    raise newException(ClientDisconnected, client.address)

proc recv*[T](client: Client, kind: typedesc[T]): Future[T] {.async.} =
  var line: string
  try:
    line = await client.socket.recvLine()
  except:
    dbg "Could not receive line: " & client.address #getCurrentExceptionMsg()
  if line == "":
    raise newException(ClientDisconnected, client.address)

  var js: JsonNode = JsonNode() # Declare an empty one to do not crash later
  try:
    js = line.parseJson()
  except:
    dbg "Could not parse json. KILL CLIENT: " & client.address
    dbg getCurrentExceptionMsg()
    client.kill()
    raise newException(ClientDisconnected, client.address)

  try:
    ## TODO the crash is fixed in nim Devel, ignore for now (i'am on Nim 1.4)
    result = js.to(T)
  except:
    dbg "Could not convert json to " & $T & " KILL CLIENT:" & client.address
    echo line
    echo js
    client.kill()
    raise newException(ClientDisconnected, client.address)

  const kindName = ($kind).split("_")[^1]

  if $result.kind != kindName:
    dbg "kind does not fit got: " & $result.kind & " expected: " & kindName
    client.kill()
    raise newException(ClientDisconnected, client.address)


proc sendGood*(client: Client, fid = -1) {.async.} =
  var good = newMsg Message_GOOD
  good.fid = fid
  await client.send(good)

proc sendBad*(client: Client) {.async.} =
  await client.send(newMsg Message_BAD)

proc sendViolation*(client: Client) {.async.} =
  await client.send(newMsg Message_PROTOCOLVIOLATION)
