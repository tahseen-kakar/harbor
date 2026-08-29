# Harbor 1.7.0

Harbor 1.7.0 adds selective torrent downloads and makes interrupted downloads safer to recover.

## Highlights

- Preview the files inside a `.torrent` file or magnet link before you add it.
- Select only the torrent files that you want to download.
- Recover interrupted direct, browser, media, and torrent downloads more reliably after Harbor restarts.
- Import compatible partial downloads from older Harbor versions instead of starting them again.
- Fix aria2 ownership verification so the torrent engine starts reliably and stale processes remain protected.
- Fix duplicate magnet seeding and several startup and media-completion edge cases.

Special thanks to [@QZGao](https://github.com/QZGao) for the major download recovery and reliability work included in this release.
