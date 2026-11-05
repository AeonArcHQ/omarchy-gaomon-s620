# Coding standards

Read during review. `tests/check.sh` enforces the mechanical rules; these are the judgement calls.

## Every setting rests on an observation

Each panel option or IPC field that becomes a Hyprland setting, and each express key action, has an **Observed** entry in `docs/re/findings.md` saying it was seen working on the tablet (date, and the command or test). An option backed only by an **Inferred** or **Unknown** entry stays out of the panel until it is observed.

The same bar holds for the docs: `findings.md`, `vendor-app.md` and the README state as working only what an Observed entry backs.

## Reads like the sibling plugin

The plugin follows `com.aeonarc.delux-m900`: `Service.qml` owns the processes, the panel owns the UI, `Model.js` holds the rules and is where tests reach them, and the Python helper only moves bytes. Logic that decides something (what to save, which key to release) belongs in `Model.js`, not in QML handlers.
