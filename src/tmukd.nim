import sets, mpv, network, parsecfg, tables
import filesys
import trepeatKind
type
  Mukd* = ref object
    server*: AsyncSocket
    running*: bool
    ctx*: ptr handle
    listening*: HashSet[Client]
    config*: Config
    clientFs*: Table[Client, Filesystem]
    repeatKind*: RepeatKind