import ../types/[tmukdstatus, tmukd]
import ../lib/mpvcontrol
import json

proc getMukdStatus*(mukd: Mukd): MukdStatus =
  result = MukdStatus()
  result.pause = mukd.ctx.getPause()
  result.timePos = mukd.ctx.getTimePos()
  result.currentSongIdx = mukd.ctx.getPlaylistPlayIndex()
  result.volume = mukd.ctx.getVolume()
  result.mute = mukd.ctx.getMute()

proc applyMukdStatus*(mukd: Mukd, mukdStatus: MukdStatus) =
  mukd.ctx.setPause(mukdStatus.pause)
  mukd.ctx.playlistPlayIndex(mukdStatus.currentSongIdx)
  mukd.ctx.setTimePos(mukdStatus.timePos)
  mukd.ctx.setVolume(mukdStatus.volume)
  mukd.ctx.setMute(mukdStatus.mute)

proc setMukdStatus*(mukd: Mukd, mukdStatus: MukdStatus) =
  mukd.ctx.setPause(mukdStatus.pause)
  mukd.ctx.playlistPlayIndex(mukdStatus.currentSongIdx)

proc storeMukdStatus*(mukdStatus: MukdStatus, path: string) =
  writeFile(path, $ %* mukdStatus)

proc loadMukdStatus*(path: string): MukdStatus =
  return readFile(path).parseJson().to(MukdStatus)