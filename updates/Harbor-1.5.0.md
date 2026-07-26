# Harbor 1.5.0

## Torrent workflow

- Automatically discover new `.torrent` files from an optional watched folder, both at launch and while Harbor is running.
- Choose separate default destinations for regular downloads and torrents.
- Keep completed torrents seeding, stop seeding to mark them completed, and resume seeding later.
- Remove downloads from Harbor alone or move their downloaded data to Trash.
- Move a torrent’s source `.torrent` file to Trash when removing it from Harbor.

## Bandwidth and interface

- Quickly enable or disable global download and upload limits from the toolbar.
- Use a redesigned, tabbed Settings window with clearer download, torrent, bandwidth, update, and acknowledgment sections.
- Inspect download details in a cleaner panel that stays out of the way until a download is selected.

## Reliability

- Show meaningful torrent names in completion notifications.
- Follow magnet metadata downloads through to their real payload, fixing torrents that could previously appear as tiny metadata-only files.
- Improve torrent restoration, deduplication, watched-file cleanup, low-speed throttling, and shutdown handling.
- Make “Remove and Move Data to Trash” operate on the exact downloaded payload instead of unrelated files in an existing folder.
