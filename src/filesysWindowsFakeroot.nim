import psutil

proc getFakeRoot*(): seq[string] =
  for disk in disk_partitions():
    result.add disk.device