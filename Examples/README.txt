Contexta Horizon — example data
===============================

sample-mail.mbox is a small mailbox of 11 made-up messages (fictional people at example.com, fictional
projects "Harborline", "Atlas" and "Northfield"). It contains no real data. Use it to see what Horizon does
before you import anything of your own.

Try it
  1. Open Contexta Horizon and choose "Sources & Settings".
  2. Press "Import…" and choose sample-mail.mbox.
  3. Go back to the simple view. Suggested topics appear (Harborline, Atlas, Northfield).
     Type a task such as "Follow up on the Harborline quote", check the text shown, then press Copy.

Horizon keeps only each message's subject and date — never the body or the addresses.

About the dates
  Horizon shows the last 3 months by default, and 6 months at most (or a custom period of your choice).
  The messages in sample-mail.mbox are dated in the few weeks before the day the file was made, so an old
  copy gradually falls out of the default view. If no topics appear:
    - make a fresh copy dated relative to today:   bash make-sample.sh
      and import it again (the fresh copy is added as new records), or
    - in Sources & Settings choose "6 months", or "Custom" with dates that cover the sample.

Removing the example
  Imports are plain files in ~/WorkIndex/horizon-v1/imports/. Delete the file whose name ends in
  "sample-mail.jsonl", then press "Reread Sources".
