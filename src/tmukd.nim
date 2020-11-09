import sets, mpv, network, parsecfg
import filesys
import trepeatKind
type
  Mukd* = ref object
    server*: AsyncSocket
    running*: bool
    ctx*: ptr handle
    listening*: HashSet[Client]
    config*: Config
    fs*: Filesystem
    repeatKind*: RepeatKind