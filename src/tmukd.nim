import sets, mpv, network, parsecfg, tables, auth
import filesys
import trepeatKind
import tmukdstatus
type
  Mukd* = ref object
    server*: AsyncSocket
    running*: bool
    ctx*: ptr handle
    listening*: HashSet[Client]
    config*: Config
    clientFs*: Table[Client, Filesystem]
    repeatKind*: RepeatKind
    allowedUploadExtensions*: HashSet[string]
    users*: Users