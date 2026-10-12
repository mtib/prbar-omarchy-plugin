# prbar-omarchy-plugin

Omarchy shell bar widget (id `mtib.prbar`); repo root is the plugin dir. See README.md for behaviour.

## Dev loop gotchas
- The shell runs with the file watcher disabled: QML edits need a shell restart to apply (`rescanPlugins` / plugin disable+enable do not reload them). Restarting can fail with `EGL not available` in software-GL VMs and leave no bar; recover with
  `hyprctl dispatch 'hl.dsp.exec_cmd("env QT_QUICK_BACKEND=software omarchy-launch-shell")'`. Batch edits, restart once.
- Never name root properties `data` or `queue` (shadowing makes bindings undefined and the pill invisible).
- Toast click-to-open uses the `omarchy-exec-argv` hint (JSON argv); libnotify `-A` actions only fire as `default` and need a live sender.
- Notification mode/timer state is applied locally first, persisted by `fetch.sh set-notify`; do not wait on a poll to reflect it.
- Test the data layer standalone: `./fetch.sh | jq '{d:(.direct|length),t:(.team|length)}'`.
