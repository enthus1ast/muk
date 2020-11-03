from json import JsonNode
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
    PAUSE,
    TOGGLE_PAUSE
  # FanoutDataKind* {.pure.} = enum
    # UNKNOWN
    # METADATA
  Control_Client_LOADFILE* = string
  # Control_Client_LOADFILE* = string
  # Control_LOADFILE* = string
  Message_Client_CONTROL* = object of Message
    data*: JsonNode
    controlKind*: ControlKind
  Message_Server_AUTH* = object of Message
  Message_GOOD* = object of Message
  Message_BAD* = object of Message
  Message_Server_PURPOSE* = object of Message
  Message_Client_PURPOSE* = object of Message
    socketPurpose*: SocketPurpose
  Message_PROTOCOLVIOLATION* = object of Message
    error*: string

  # DataKind* = enum

  Message_Server_FANOUT* = object of Message
    # dataKind*: DataKind
    data*: JsonNode