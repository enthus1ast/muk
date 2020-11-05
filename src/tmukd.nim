import sets, mpv, network
type
  Mukd* = ref object
    server*: AsyncSocket
    running*: bool
    ctx*: ptr handle
    listening*: HashSet[Client]
