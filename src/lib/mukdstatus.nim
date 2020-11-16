import ../types/tmukdstatus
import ../lib/mpvcontrol
import json

proc getMukdStatus*(mukd: Mukd): MukdStatus =
  result = MukdStatus()
  result.pause = mukd.ctx.getPause()
  result.timPos = mukd.ctx.getTimePos()
  result.currentSongIdx = mukd.ctx.getPlaylistPlayIndex()

proc setMukdStatus*(mukd: Mukd, mukdStatus: MukdStatus) =
  mukd.ctx.setPause(mukdStatus.pause)
  mukd.ctx.playlistPlayIndex(mukdStatus.currentSongIdx)

proc storeMukdStatus*(mukdStatus: MukdStatus, path: string) =
  writeFile(path, $ %* mukdStatus)

proc loadMukdStatus*(path: string): MukdStatus =
  return readFile(path).parseJson().to(MukdStatus)