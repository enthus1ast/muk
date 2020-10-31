MUK
====

Prototype (!!!) of a crossplattform terminal music player.
Inspired by moc and mpd.

Uses the mighty `mpv` as audio backend.

'mukke' is a german slang for music.


Keyboard Binding
----------------



|     Pane       |    KEY     | Action  |
| ------------- |:-------------:| -----:|
| BOTH | {TAB}  | Switch Pane Filesystem <-> Playlist |
| BOTH | {j}/{k}/{DOWN}/{UP} | DOWN/UP Selection |
| BOTH | {h}/{l}/{LEFT}/{RIGHT} | Seek backwards/forwars |
| BOTH | {ShiftH}/{ShiftL} | Seek backwards/forwars faster |
| BOTH | {-}/{+} | Volume DOWN/UP |
| BOTH | {ShiftJ, ShifK} | Next/Previous song |
| BOTH | {Enter} | Play/Open |
| BOTH | {m} | Mute/Unmute |
| BOTH | {p} | Pause/Resum |
| BOTH | {p} | Pause/Resum |
| BOTH | {v} | Show/Hide video |
| BOTH | {c} | Clear the playlist |
| BOTH | ~~{g}/{/}~~ | Search |
| BOTH | {?}/{F1} | Help |
| BOTH | ~~{ESC}~~ | Exit out of search/help/lyrics etc. |
| Filesystem | {ShiftG} | Search recursive |
| Filesystem | {:}/{Backspace} | One folder up |
| Filesystem | {a} | Add song/directory to playlist |
| Playlist | {d}/{Del} | Remove a song from the playlist |
| Playlist | ~~??????~~ | Fetch lyrics |



Features
-------

- [ ] Network Client/Server
  - [ ] standalone gui
  - [ ] standalone audio backend
  - [ ] network code
    - [ ] secure networking
- [ ] One click, up and download, music from client <-> server
- [ ] ~~Lyric fetcher~~ (low priority)
- [ ] Cross platform
  - [x] Linux
  - [x] Windows
  - [ ] ~~Macos~~ (low priority, need testers)
  - [ ] ssh, tmux, etc..
- [x] Video support when running on a window manager
- [x] mouse support
- [ ] ~~music library~~ (low priority, you have a clean music folder right? ;)
- [ ] custom keybindings
- [ ] custom colorscheme

Network Protocol
----------------

TODO

Download / Install
---------

TODO
- ~~install via nimble:~~
  - ~~`nimble install muk`~~
- ~~[linux, windows, macos libraries on the release page]()~~ yet to come

Build from source
-----------------

TODO

Changelog
--------

TODO
- ~~0.1.0 (First usable version)~~

- 0.0.9 (Prototype)
  - STUFF

Technologie / Credits
-----------

- [x] [Nim](https://nim-lang.org/) (programming language)
- [x] [illwill](https://github.com/johnnovak/illwill) (terminal library for nim)
- [x] [illwillWidgets](https://github.com/enthus1ast/illwillWidgets) (widget library for illwill)
- [x] [mpv/libmpv](https://github.com/mpv-player/mpv) (music/video backend)
- [ ] ~~[LyricFetcher]()~~ yet to be written :)