#!/bin/bash
# macOS: writes three fictional messages to stdout. Redirect to a new .mbox file.
set -eu
subjects=('Harborline quote: revised carton specification' 'Harborline quote: confirm the sample delivery date' 'Harborline artwork: packaging proof for review')
for n in 0 1 2; do
  day=$((n+1)); stamp=$(LC_ALL=C date -u -v-"${day}"d '+%a, %d %b %Y 09:00:00 +0000'); envelope=$(LC_ALL=C date -u -v-"${day}"d '+%a %b %e 09:00:00 %Y');
  printf 'From demo@example.invalid %s\nDate: %s\nFrom: Demo <demo@example.invalid>\nSubject: %s\nMessage-ID: <harborline-demo-%s-%s@example.invalid>\n\nFictional example. Only the subject and timestamp matter for this demo.\n\n' "$envelope" "$stamp" "${subjects[$n]}" "$day" "$(date -u +%Y%m%d)"
done
