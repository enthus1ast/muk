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
    PROTOCOLVIOLATION
  Message* = object of RootObj
    kind*: MessageTypes
  Message_Client_AUTH* = object of Message
    username*: string
    password*: string
  Message_Server_AUTH* = object of Message
  Message_Server_GOOD* = object of Message
  Message_Server_BAD* = object of Message
  Message_Client_GOOD* = object of Message
  Message_Client_BAD* = object of Message
  Message_Server_PURPOSE* = object of Message
  Message_Client_PURPOSE* = object of Message
    socketPurpose*: SocketPurpose
  Message_Server_PROTOCOLVIOLATION* = object of Message