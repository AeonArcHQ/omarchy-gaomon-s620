# Kernel driver by default, OpenTabletDriver as an optional backend

The plugin is meant for many Omarchy users, and `omarchy plugin add` only clones a repository: it cannot install packages or block kernel modules. So the plugin works on the kernel's `hid-uclogic` driver out of the box, and when the OpenTabletDriver daemon is running it switches to it and offers what only OTD can do (90°/270° rotation, a pressure curve). The cost is two implementations of each shared setting (screen, area, pressure, keys), one per backend.

## Considered Options

- **OpenTabletDriver only**: covers every feature, but each user must install .NET and an AUR package that blocks `hid_uclogic`.
- **Kernel driver only**: no rotation to 90°/270° and no pressure curve, ever (`docs/re/findings.md`, `docs/re/opentabletdriver.md`).
