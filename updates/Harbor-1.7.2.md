## What’s New

- Added a torrent network interface setting, including named VPN services and raw network interfaces.
- Harbor now pauses torrents and active seeders when the selected interface disappears, then resumes only the transfers it paused when the interface returns.
- Network-suspended torrents remain recoverable across app relaunches, and queued torrents wait safely while the selected interface is unavailable.
- Moved the Network controls below Seeding in Torrent settings.

Thanks to [@InvalidPandaa](https://github.com/InvalidPandaa) for the network binding implementation in [#77](https://github.com/thsnkhn/harbor/pull/77).

Network binding currently applies to torrent traffic only. Regular and media downloads are unchanged.
