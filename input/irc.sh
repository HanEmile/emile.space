#!/bin/bash
ID=$(date +%s)
SERVER="${IRC_SERVER:-irc.emile.space}"
PORT="${IRC_PORT:-6697}"
NICKNAME="${IRC_NICK:-$(whoami)}"
CHANNEL="${IRC_CHANNEL:-#general}"

PIPE=$(mktemp -u)
mkfifo "$PIPE"
trap 'rm -f "$PIPE"' EXIT
(
  echo "NICK $NICKNAME"
  echo "USER $NICKNAME 0 * :$NICKNAME"
  echo "JOIN $CHANNEL"
  while IFS= read -r line; do
    echo "PRIVMSG $CHANNEL :$line"
  done < /dev/tty
) > "$PIPE" &
ncat --ssl -C "$SERVER" "$PORT" < "$PIPE" | while IFS= read -r server_line; do
    echo -e "$server_line" | sed "s/!.*$CHANNEL :/> /g"
    if [[ "$server_line" == PING* ]]; then
        target=${server_line#PING }
        target=$(echo "$target" | tr -d '\r')
        echo "PONG $target" > "$PIPE"
    fi
done
