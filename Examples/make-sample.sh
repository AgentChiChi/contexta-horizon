#!/bin/bash
# Writes sample-mail.mbox: a small, entirely made-up mailbox for trying Contexta Horizon on an empty install.
# Every name, company and address is fictional (example.com). Nothing is read from this Mac and nothing is sent.
#
#   bash make-sample.sh            writes sample-mail.mbox next to this script
#   bash make-sample.sh <file>     writes it somewhere else
#
# The messages are dated a few days back from TODAY. Horizon shows the last 3 months by default (6 months at most),
# so a copy made long ago slowly ages out of view; run this again for a fresh one.
set -euo pipefail
out="${1:-$(cd "$(dirname "$0")" && pwd)/sample-mail.mbox}"
stamp=$(date "+%Y%m%d")
tmp="$out.tmp.$$"
: > "$tmp"
n=0
# days ago | hour | Gmail-style label | from | to | subject
while IFS='|' read -r days hour label from to subject; do
  [ -z "$days" ] && continue
  n=$((n+1))
  envelope=$(LC_ALL=C date -v-"${days}"d "+%a %b %e ${hour}:15:00 %Y")
  header=$(LC_ALL=C date -v-"${days}"d "+%a, %d %b %Y ${hour}:15:00 %z")
  {
    echo "From sample@example.com $envelope"
    echo "X-Gmail-Labels: $label"
    echo "From: $from"
    echo "To: $to"
    echo "Subject: $subject"
    echo "Date: $header"
    echo "Message-ID: <sample-$(printf '%02d' "$n")-$stamp@example.com>"
    echo
    echo "This is a made-up message for trying Contexta Horizon. It describes no real person, company or event."
    echo
  } >> "$tmp"
done <<'LIST'
2|10|Inbox|Dana Example <dana@example.com>|Sam Example <sam@example.com>|Re: Harborline quote revision
3|16|Sent|Sam Example <sam@example.com>|Dana Example <dana@example.com>|Harborline quote revision
6|09|Inbox|Dana Example <dana@example.com>|Sam Example <sam@example.com>|Harborline contract draft for review
8|14|Inbox|Dana Example <dana@example.com>|Sam Example <sam@example.com>|Harborline delivery dates
9|11|Inbox|Lee Example <lee@example.com>|Sam Example <sam@example.com>|Atlas onboarding checklist
12|15|Sent|Sam Example <sam@example.com>|Lee Example <lee@example.com>|Atlas onboarding schedule
15|10|Inbox|Pat Example <pat@example.com>|Sam Example <sam@example.com>|Northfield invoice question
16|09|Sent|Sam Example <sam@example.com>|Pat Example <pat@example.com>|Re: Northfield invoice question
18|12|Inbox|Lee Example <lee@example.com>|Sam Example <sam@example.com>|Team lunch on Friday
21|17|Sent|Sam Example <sam@example.com>|Lee Example <lee@example.com>|Atlas design feedback
24|10|Inbox|Pat Example <pat@example.com>|Sam Example <sam@example.com>|Northfield renewal terms
LIST
mv -f "$tmp" "$out"
echo "Wrote $n made-up messages to $out (dated $(date -v-24d "+%Y-%m-%d") to $(date -v-2d "+%Y-%m-%d"))"
