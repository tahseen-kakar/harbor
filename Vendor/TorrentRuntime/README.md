# Bundled aria2 Runtime

This directory holds the self-contained `aria2c` runtime that Harbor ships for torrent support.

For release builds, stage the runtime with:

```bash
./Scripts/vendor-aria2-runtime.sh
```

That script populates `TorrentRuntime/<arch>/bin` and `TorrentRuntime/<arch>/lib` with the `aria2c` binary and its non-system dynamic libraries so Harbor can launch torrents without requiring Homebrew on the user’s Mac.
