from json import JsonNode
import tsonginfo
import tplaylist
import trepeatKind
type
  SocketPurpose* {.pure.} = enum
    Unknown
    Listening, ## Client never initial sends, server sends status changes...
    Control ## Server never initialy sends, client sends command, server answers...
    # FileDownload, FileUpload
  MessageTypes* {.pure.} = enum
    UNKNOWN,
    FOO,
    GOOD,
    BAD,
    AUTH,
    PURPOSE,
    FANOUT,
    CONTROL,
    PROTOCOLVIOLATION
  Message* = object of RootObj
    kind*: MessageTypes
  Message_Client_AUTH* = object of Message
    username*: string
    password*: string
  ControlKind* {.pure.} = enum
    UNKNOWN,
    LOADFILE,
    LOADFILEAPPEND,
    PAUSE,
    TOGGLEPAUSE,
    SEEKRELATIVE,
    PERCENTPOS,
    TOGGLEMUTE,
    VOLUMERELATIV,
    VOLUMEPERCENT,
    PLAYINDEX,
    NEXTSONG,
    PREVSONG,
    REMOVESONG,
    CLEARPLAYLIST,
    CYCLEREPEAT,
    SETREPEAT,
    FSLS,
    FSACTION,
    FSUP,
    # FSCD,
    QUIT,
    TOGGLEVIDEO

  Control_Client_FSLS* = string
  Control_Client_FSACTION* = string
  # Control_Client_FSCD* = string

  Control_Server_FSLS* = object
    listing*: seq[string]
    currentPath*: string
  # Control_Server_ACTION* = nil # TODO ?

  Control_Client_REMOVESONG* = int
  Control_Client_SEEKRELATIVE* = float
  Control_Client_VOLUMERELATIV* = float
  Control_Client_VOLUMEPERCENT* = float
  Control_Client_PERCENTPOS* = float
  Control_Client_LOADFILE* = string
  Control_Client_LOADFILEAPPEND* = string
  Control_Client_PAUSE* = bool
  Control_Client_PLAYINDEX* = int
  Message_Client_CONTROL* = object of Message
    data*: JsonNode
    controlKind*: ControlKind
  Message_Server_CONTROL* = object of Message
    data*: JsonNode
    controlKind*: ControlKind
  Message_Server_AUTH* = object of Message
  Message_GOOD* = object of Message
    fid*: int
  Message_BAD* = object of Message
  Message_Server_PURPOSE* = object of Message
  Message_Client_PURPOSE* = object of Message
    socketPurpose*: SocketPurpose
  Message_PROTOCOLVIOLATION* = object of Message
    error*: string

  FanoutDataKind* {.pure.} = enum
    UNKNOWN,
    METADATA,
    PROGRESS,
    MUTE,
    PAUSE,
    VOLUME,
    PLAYLIST,
    REPEATKIND,
  Fanout_REPEATKIND* = RepeatKind
  Fanout_PROGRESS* = object
    percent*: float
    timePos*: float
    duration*: float
  Fanout_VOLUME* = float
  Fanout_PAUSE* = bool
  Fanout_MUTE* = bool
  Fanout_METADATA* = SongInfo
  Fanout_PLAYLIST* = PlaylistSongs
  Message_Server_FANOUT* = object of Message
    dataKind*: FanoutDataKind
    data*: JsonNode
    fid*: int
