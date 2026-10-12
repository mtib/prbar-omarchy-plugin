# prbar-omarchy-plugin

An [Omarchy](https://omarchy.org/) bar widget for the GitHub pull requests waiting on your review.
A rebuild of the macOS app [mtib/prbar](https://github.com/mtib/prbar) as an Omarchy shell plugin.

The queue lives in the top bar as `󰊤 <direct + team>`, and you get exactly one notification per PR
that newly needs you. Click the pill for the panel.

## What it shows

Every minute by default it runs two GitHub searches and splits the results into three tabs:

| Tab | What lands there |
| --- | --- |
| **Direct** | `user-review-requested:<you>`: a review is blocked on you personally |
| **Team** | `review-requested:<you>` minus the direct set: requested from a team you're on |
| **Drafts** | anything in either set that's still a draft |

Both searches use `review:required`, so a PR drops off once it no longer blocks the merge. PRs you
authored are filtered out. Drafts are left out of the bar total. Clicking a row opens the PR in your
browser.

The chip next to the tabs is the number of **distinct PRs you reviewed today** (your time zone).
Click it for a 7 or 30 day histogram. It's computed from `reviewed-by:<you>` plus each PR's own
reviews; `contributionsCollection` is not used because it silently drops private repos.

## Notifications

The bell in the panel footer cycles **All** (direct and team) → **Only direct** → **Off**. In a quiet
mode a second button picks a lapse timer (30m, 1h, 4h, 8h, or until you change it) after which it
returns to **All**. The pill shows `󰂛` and the bell turns orange while muted.

- One notification per PR, the first time it appears in Direct or Team; clicking it opens the PR.
- Drafts never notify; a draft flipped to ready does.
- The first run seeds silently. Muted periods never build a backlog.
- A PR that leaves the queue and is re-requested notifies again.

State lives in `~/.local/state/prbar-omarchy/`.

## Keys

`r` refresh · `1` `2` `3` tabs · `h` history · right/middle-click the pill to refresh.

## Settings

Refresh interval (60 to 3600 s) and sort order (recent/least recent activity, newest/oldest PR).

## Install

Requires Omarchy, [`gh`](https://cli.github.com/) (logged in with `repo` and `read:org` scopes, the
latter makes team requests visible), `jq` and `notify-send`.

```sh
omarchy plugin add https://github.com/mtib/prbar-omarchy-plugin --enable
```

Update with `omarchy plugin update`, remove with `omarchy plugin remove mtib.prbar`.

## Layout

```
manifest.json   plugin manifest (id mtib.prbar, bar-widget)
Panel.qml       pill, tabs, histogram, footer
fetch.sh        GitHub queries, bucketing, notify-once; prints one JSON document
```

## Licence

MIT
