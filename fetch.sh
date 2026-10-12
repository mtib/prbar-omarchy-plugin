#!/usr/bin/env bash
# prbar data source. Prints one JSON document for the panel and sends the
# notify-once notifications as a side effect.
#
#   fetch.sh                       refresh
#   fetch.sh set-notify MODE [MIN] MODE = all|direct|off, optional lapse after MIN minutes
set -euo pipefail

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/prbar-omarchy"
SEEN="$STATE/notified.json"
PREFS="$STATE/prefs.json"
mkdir -p "$STATE"

now() { date +%s; }

load_prefs() {
  MODE=all UNTIL=0
  if [[ -f $PREFS ]]; then
    MODE=$(jq -r '.mode // "all"' "$PREFS")
    UNTIL=$(jq -r '.until // 0' "$PREFS")
  fi
  # A timed quiet mode lapses back to "all" on the next poll.
  if [[ $UNTIL -gt 0 && $UNTIL -le $(now) ]]; then MODE=all UNTIL=0; save_prefs; fi
}

save_prefs() { jq -n --arg m "$MODE" --argjson u "$UNTIL" '{mode:$m,until:$u}' >"$PREFS"; }

if [[ ${1:-} == set-notify ]]; then
  MODE=${2:?mode} UNTIL=0
  [[ $MODE =~ ^(all|direct|off)$ ]] || { echo "bad mode: $MODE" >&2; exit 2; }
  [[ $MODE != all && ${3:-0} -gt 0 ]] && UNTIL=$(( $(now) + $3 * 60 ))
  save_prefs
  exit 0
fi

# Detached helper: one notification, click opens the PR.
if [[ ${1:-} == _notify ]]; then
  action=$(notify-send -a prbar -A open=Open -w "$3" "$4" 2>/dev/null || true)
  [[ $action == open || $action == default ]] && exec omarchy-launch-browser "$2"
  exit 0
fi

load_prefs

LOGIN=$(gh api user --jq .login)
BASE="is:pr is:open archived:false review:required -author:$LOGIN"

# Both searches keep drafts (no draft:false) and bucket client-side. Reviews are
# pulled back per PR via reviewed-by, because contributionsCollection silently
# drops private repositories.
read -r -d '' Q <<'GQL' || true
query($req:String!,$dir:String!,$rev:String!,$login:String!){
  req:search(query:$req,type:ISSUE,first:100){nodes{...PR}}
  dir:search(query:$dir,type:ISSUE,first:100){nodes{...PR}}
  rev:search(query:$rev,type:ISSUE,first:100){nodes{... on PullRequest{id reviews(first:50,author:$login){nodes{submittedAt}}}}}
}
fragment PR on PullRequest{id number title url updatedAt createdAt isDraft repository{nameWithOwner} author{login}}
GQL

RESP=$(gh api graphql \
  -f req="$BASE review-requested:$LOGIN sort:updated-desc" \
  -f dir="$BASE user-review-requested:$LOGIN sort:updated-desc" \
  -f rev="is:pr reviewed-by:$LOGIN updated:>=$(date -d '31 days ago' +%F)" \
  -f login="$LOGIN" -f query="$Q")

DAYS=$(for i in $(seq 29 -1 0); do date -d "$i days ago" +%F; done | jq -R . | jq -sc .)

OUT=$(jq -c --arg user "$LOGIN" --argjson days "$DAYS" --arg mode "$MODE" --argjson until "$UNTIL" '
  def pr: {id,number,title,url,updatedAt,createdAt,isDraft,
           repo:.repository.nameWithOwner, author:(.author.login // "ghost")};
  ([.data.dir.nodes[] | select(.id) | .id]) as $direct
  | ([.data.req.nodes[] | select(.id) | pr]) as $all
  | ([.data.rev.nodes[] | select(.id) | .id as $id
      | .reviews.nodes[] | select(.submittedAt)
      | {id:$id, day:(.submittedAt | fromdate | localtime | strftime("%Y-%m-%d"))}]
     | unique | group_by(.day) | map({key:.[0].day, value:length}) | from_entries) as $h
  | ($days | map({day:., count:($h[.] // 0)})) as $hist
  | {user:$user,
     direct: [$all[] | select(.isDraft|not) | select(.id as $i | $direct | index($i))],
     team:   [$all[] | select(.isDraft|not) | select(.id as $i | $direct | index($i) | not)],
     drafts: [$all[] | select(.isDraft)],
     today: $hist[-1].count, history: $hist,
     notify: {mode:$mode, until:$until}}
  | .direct |= map(.direct = true) | .team |= map(.direct = false)
' <<<"$RESP")

# Notify once per PR on first appearance in Direct/Team. The seen set is always
# rewritten to the current queue, so a muted period never builds a backlog, a PR
# that leaves and is re-requested notifies again, and the first run seeds silently.
if [[ -f $SEEN ]]; then
  case $MODE in
    all)    SEL='.direct + .team' ;;
    direct) SEL='.direct' ;;
    off)    SEL='[]' ;;
  esac
  jq -c --slurpfile seen "$SEEN" "($SEL)[] | select(.id as \$i | \$seen[0] | index(\$i) | not)" <<<"$OUT" |
  while read -r p; do
    url=$(jq -r .url <<<"$p")
    title="$(jq -r '"\(.repo) #\(.number)"' <<<"$p")"
    body="$(jq -r '"\(.title)\nfrom \(.author)"' <<<"$p")"
    setsid -f "$0" _notify "$url" "$title" "$body" >/dev/null 2>&1 </dev/null
  done
fi
jq -c '[.direct[].id, .team[].id]' <<<"$OUT" >"$SEEN"

printf '%s\n' "$OUT"
