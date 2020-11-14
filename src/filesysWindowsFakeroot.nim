import psutil

proc getFakeRoot*(): seq[string] =
  ## Renders a "fake root" on windows:
  ## C:\\ D:\\ etc..
  for disk in disk_partitions():
    result.add disk.device