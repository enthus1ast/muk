# this is mukd user manager library and stand alone tool for manage mukd network users

import securehash, tables, json, os
const SALT = "mukusertablefoobaa"
type
  Username* = string
  Users* = Table[Username, User]
  User* = object
    username: string
    passwordHash: string

proc hashPw*(username, password: string): string =
  result = $secureHash(username & password & SALT)

proc newUser*(username, password: string): User =
  result = User()
  result.username = username
  result.passwordHash = hashPw(username, password)

proc loadUsers*(path: string): Users =
  result = initTable[Username, User]()
  if not fileExists(path): return result
  for line in path.lines:
    let user = parseJson(line).to(User)
    result[user.username] = user

proc storeUsers*(path: string, users: Users) =
  var fh = open(path, fmWrite)
  for user in users.values:
    let line = $ %* user
    fh.writeLine(line)
  fh.close()

proc valid*(users: Users, username, password: string): bool =
  if not users.contains(username): return false
  let user = users[username]
  return user.passwordHash == hashPw(username, password)

proc addUser*(users: var Users, username, password: string) =
  users[username] = newUser(username, password)

proc addUser*(path, username, password: string) =
  var users = loadUsers(path)
  users.addUser(username, password)
  storeUsers(path, users)



when isMainModule:
  import cligen
  proc add(username: string, password: string): int =
    addUser("config/users.db", username, password)
    return 0
  dispatchMulti([auth.add])

