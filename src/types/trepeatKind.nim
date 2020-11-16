type
  RepeatKind* {.pure.} =  enum
    None, Song, List

proc cycleRepeatKind*(repeatKind: RepeatKind): RepeatKind =
  case repeatKind
  of None: return Song
  of Song: return List
  of List: return None