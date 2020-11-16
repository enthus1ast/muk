# import json
# type
#   MukdStatus* = object
#     ## This is used to periodically store the
#     ## Status to the filesystem, to load it on mukd restart
#     currentSong*: int
#     pause*: bool
#     progress*: int

# proc store*(mukdStatus: MukdStatus, path: string) =
#   writeFile(path, $ %* mukdStatus)

# proc loadMukdStatus*(path: string): MukdStatus =
#   return readFile(path).parseJson().to(MukdStatus)^
