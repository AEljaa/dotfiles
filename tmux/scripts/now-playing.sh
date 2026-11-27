#!/usr/bin/env bash
# tmux status bar: "♪ song – artist" while music is playing, nothing when paused / closed.
#   macOS: Spotify or Apple Music (AppleScript; only asks an app that's already open,
#          so it never launches Spotify by itself)
#   Linux: any player that supports MPRIS (Spotify, browsers, VLC...) via `playerctl`,
#          if it's installed
#   anything else (e.g. WSL): shows nothing
# Long names are cut to ~32 characters.

case "$(uname -s)" in
  Darwin)
    for app in Spotify Music; do
      pgrep -xq "$app" || continue
      out=$(osascript 2>/dev/null <<OSA
tell application "$app"
  if player state is playing then
    set s to (name of current track) & " – " & (artist of current track)
    if length of s > 32 then set s to (text 1 thru 31 of s) & "…"
    return "♪ " & s & "  "
  end if
end tell
OSA
)
      # a "#" in a song name would be read as tmux formatting, so drop it
      [ -n "$out" ] && { printf '%s' "$out" | tr -d '#'; exit 0; }
    done
    ;;
  Linux)
    command -v playerctl >/dev/null || exit 0
    [ "$(playerctl status 2>/dev/null)" = Playing ] || exit 0
    s=$(playerctl metadata --format '{{title}} – {{artist}}' 2>/dev/null) || exit 0
    s=${s//#/}
    [ ${#s} -gt 32 ] && s="${s:0:31}…"
    [ -n "$s" ] && printf '♪ %s  ' "$s"
    ;;
esac
exit 0
