import templates, json, strutils
import mpv
import tsonginfo
import tplaylist

proc getSongTitle*(ctx: ptr handle): string =
  tryIgnore: result = ctx.get_property("media-title")

proc getMetadata*(ctx: ptr handle): JsonNode =
  ## returns the raw metadata, must be normalized!
  try:
    result = ctx.get_property("filtered-metadata").parseJson()
  except:
    result = %* {}

proc normalizeMetadata*(js: JsonNode): SongInfo =
  result = SongInfo()
  for rawKey, rawVal in js:
    let key = rawKey.toLowerAscii()
    if   key == "title": result.title = rawVal.getStr()
    elif key == "album": result.album = rawVal.getStr()
    elif key == "artist": result.artist = rawVal.getStr()

proc getSongPath*(ctx: ptr handle): string =
  tryIgnore: result = ctx.get_property("path")

proc seekRelative*(ctx: ptr handle, seconds: float = 0.0) =
  tryIgnore:ctx.command(@["seek", $seconds, "relative", "exact"])

proc volumeRelative*(ctx: ptr handle, num: float = 0.0) =
  tryIgnore:ctx.command(@["add", "volume", $num])

proc getVolume*(ctx: ptr handle): float =
  tryIgnore: return ctx.get_property("volume").parseFloat()

proc pause*(ctx: ptr handle) =
  tryIgnore: ctx.command(@["pause"])

proc getPause*(ctx: ptr handle): bool =
  tryIgnore: result = ctx.get_property("pause").parseBool()

proc togglePause*(ctx: ptr handle): bool =
  tryIgnore:
    ctx.command(@["cycle", "pause"])
    return ctx.getPause()

proc setPause*(ctx: ptr handle, pause: bool) =
  tryIgnore: ctx.command(@["pause", $pause])

proc getMute*(ctx: ptr handle): bool =
  tryIgnore: result = ctx.get_property("mute").parseBool()

proc toggleMute*(ctx: ptr handle): bool =
  tryIgnore:
    ctx.command(@["cycle", "mute"])
    return ctx.getMute()

proc loadfile*(ctx: ptr handle, file: string) =
  if file == "":
    tryIgnore ctx.command("stop")
  else:
    tryIgnore ctx.command("loadfile", file)

proc addToPlaylist*(ctx: ptr handle, file: string) =
  tryIgnore ctx.command(@["loadfile", $file, "append"])

proc addToPlaylistAndPlay*(ctx: ptr handle, file: string) =
  tryIgnore ctx.command(@["loadfile", $file, "append-play"])
  ## TODO append-play does not play the file when another one is playing already...
  ## TODO So append , skip to latest should work
  # tryIgnore ctx.command(@)
  # addToPlaylistAndPlay

proc playlistPlayIndex*(ctx: ptr handle, index: int) =
  ## TODO we send both for newer and older mpv's ... test if this is an issue..
  tryIgnore ctx.command(@["playlist-play-index", $index]) # for newer mpv versions ?
  tryIgnore ctx.command(@["playlist-pos", $index]) # for older mpv versions ??
  tryIgnore ctx.command(@["playlist-start", $index]) # for older mpv versions ???


proc nextFromPlaylist*(ctx: ptr handle) =
  tryIgnore ctx.command("playlist-next")

proc prevFromPlaylist*(ctx: ptr handle) =
  tryIgnore ctx.command("playlist-prev")

proc clearPlaylist*(ctx: ptr handle) =
  tryIgnore ctx.command("stop")

proc removeSong*(ctx: ptr handle, index: int) =
  tryIgnore ctx.command("playlist-remove", $index)

proc getPlaylist*(ctx: ptr handle): PlaylistSongs =
  let js = ($ctx.get_property("playlist")).parseJson()
  # echo js
  for dic in js.getElems:
    var elem = PlaylistSong()

    if dic.contains("id"):
      elem.id = dic["id"].getInt()

    if dic.contains("filename"):
      elem.filename = dic["filename"].getStr()

    if dic.contains("current"):
      elem.current = dic["current"].getBool()
    else:
      elem.current = false
    result.add elem

proc getProgressInPercent*(ctx: ptr handle): float =
  result = 0.0
  tryIgnore: result = (parseFloat ctx.get_property("percent-pos")).clamp(0.0, 100.0)

proc getTimePos*(ctx: ptr handle): float =
  tryIgnore: result = parseFloat(ctx.get_property("time-pos"))

proc getDuration*(ctx: ptr handle): float =
  tryIgnore: result = parseFloat(ctx.get_property("duration"))

proc setProgressInPercent*(ctx: ptr handle, progress: float) =
  tryIgnore: ctx.set_property("percent-pos", $progress)

proc loopFile*(ctx: ptr handle, enabled: bool) =
  var param = ""
  if enabled:
    param = "inf"
  else:
    param = "no"
  tryIgnore: ctx.set_property("loop-file", $param)

proc loopPlaylist*(ctx: ptr handle, enabled: bool) =
  var param = ""
  if enabled:
    param = "inf"
  else:
    param = "no"
  tryIgnore: ctx.set_property("loop-playlistT", $param)

proc toggleVideo*(ctx: ptr handle) =
  tryIgnore ctx.command(@["cycle", "video"])