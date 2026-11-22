# Getting started with Contexta Horizon 0.5.1

[한국어 가이드](GUIDE.ko.md)

Contexta Horizon helps you pick up a task by finding a short list of dated references on your Mac. It shows titles and where they came from, not an AI-generated answer. Start with the fictional sample; you don't need to connect an account or import your own records.

## Install or upgrade

1. On an **Apple Silicon Mac running macOS 13 or later**, open the [v0.5.1 release page](https://github.com/AgentChiChi/contexta-horizon/releases/tag/v0.5.1) and download [Contexta-Horizon-0.5.1-macOS-arm64.zip](https://github.com/AgentChiChi/contexta-horizon/releases/download/v0.5.1/Contexta-Horizon-0.5.1-macOS-arm64.zip). The prebuilt app is not for Intel Macs. If the release lists a SHA-256 checksum, compare it with the output of `shasum -a 256 Contexta-Horizon-0.5.1-macOS-arm64.zip` run from the download folder.
2. Unzip the archive in Finder, move `contexta-horizon.app` to **Applications**, and open it. If you plan to use the optional Aside skill, use the **Applications** folder inside your home folder (`~/Applications`), creating it if needed. Aside's helper does not look in the system-wide `/Applications` folder.
3. **Upgrading?** Right-click the calendar icon in the menu bar and select **Quit Contexta Horizon**. Replace the old app bundle in your chosen Applications folder, then open the new one. Keep only one installed copy. Replacing the app bundle does not remove the local imports stored separately under `~/WorkIndex`.

**macOS security:** This release is ad-hoc signed and **not Apple-notarized**, so macOS may block it. If you see a security warning, stop and verify where the ZIP came from. Do not disable Gatekeeper or bypass a security warning. If the downloaded app cannot be used under your Mac's security policy, leave it unopened. If appropriate, review and build the source locally instead: with Apple's Command Line Tools installed, run `bash build.sh` from the extracted source folder. It builds `dist/contexta-horizon.app`, generates the example, and runs checks without installing the app.

## Try it with fictional mail

1. Download [sample-mail.mbox](https://github.com/AgentChiChi/contexta-horizon/releases/download/v0.5.1/sample-mail.mbox) from the release. It contains 11 made-up messages about Harborline, Atlas, and Northfield.
2. Click the calendar icon in the menu bar. Choose **Sources & Settings → Import…**, select the mailbox, and wait for the import to finish. Make sure **Mail** and **Imports** are on, then click **‹ Simple View**.
3. Choose **Harborline** if it's suggested, or type **Follow up on the Harborline quote**. Read the dates, source types, and titles in the preview. A title about a quote revision tells you where to look, not that the revision was accepted.

The default period is the last **3 calendar months**. If the sample's dates fall outside it, choose **6 months** or an applicable **Custom** range of up to six months in **Sources & Settings**. Or download **Source code (zip)** from the release, unzip it, open Terminal in the extracted source folder, and run:

```bash
bash Examples/make-sample.sh "$HOME/Downloads/sample-mail-today.mbox"
```

This writes 11 fictional messages to your Downloads folder, dated 2–24 days before the day you run it. It reads no personal records and sends nothing. Import the new mailbox and use a period that includes those dates. A new day's sample can add records; reimporting the same records skips duplicates.

## Use your own records and share a reviewed copy

- In **Sources & Settings → Import…**, choose a supported local file: an extracted ChatGPT or Claude `conversations.json`, an Apple Mail or Gmail Takeout `.mbox`, or a compatible normalized `.jsonl`. These are snapshots, not live connections. File references require a compatible local WorkIndex file list; Horizon does not crawl your disk or discover your accounts.
- In **Simple View**, type a short task with a distinctive project name, or pick a suggestion. Review the exact text you would share. Dates are record dates, and inferred links and titles aren't proof that something happened. If you need a price, a contract clause, or a confirmed decision, check the original.
- Click **Copy** only when you're happy with the preview. Pressing Return does not copy. Paste the text yourself into a chat you choose, such as ChatGPT, Claude, or Aside, or into a document. The copy contains no attachments or full message bodies. Add a specific excerpt separately only if you mean to share it.

**Privacy:** Horizon does not call an AI service. It uses local records within the selected period and source switches: file listing metadata, conversation titles and times, and mail subjects and dates. Mail imports do not retain message bodies or sender and recipient addresses as records; chat imports retain title and time metadata, not conversation text. The handoff does not include document contents. A title may still reveal a name, project, or sensitive topic. Once you share text in a chat, that provider's processing, storage, and privacy rules apply; local lookup does not make the chat private.

## Optional: let Aside find earlier work

You can always paste a reviewed copy into Aside without installing a skill. Install the skill only if you want Aside to retrieve references in the current chat when you ask about earlier work.

1. Put Horizon 0.5.1 at `~/Applications/contexta-horizon.app`, as described above. In Terminal, run `node --version`. If the command is missing, install a supported Node.js LTS release, then run it again. Node.js is needed for the Aside helper, not the Mac app's normal Copy flow.
2. Download and unzip [Horizon-Aside-skill.zip](https://github.com/AgentChiChi/contexta-horizon/releases/download/v0.5.1/Horizon-Aside-skill.zip). Copy the entire `horizon-resume` folder, with `SKILL.md` and `scripts/lookup.mjs` together, into `skills/user` under **your active Aside account's root folder**. The resulting path should be `<Aside account root>/skills/user/horizon-resume/SKILL.md`, without an extra archive folder in between. Open a new Aside chat after installation. To check discovery without looking up your records, ask whether the `horizon-resume` skill is available.
3. Ask **“Where did we leave the Harborline quote?”** No wake word or command is required. A follow-up like **“Let's revisit that quote”** can work when the current chat makes the project clear. If the answer is already in the chat, Aside uses it; if the project is unclear, it asks which one you mean. A bare **“try again”** or an ordinary web search does not trigger a local lookup. Say **“Use only this chat”** to rule lookup out.

The skill sends a short topic query to the local app, using the same saved period and source switches. If it finds a match, the dated reference text enters the **current Aside chat** and may be processed by its model. This path does not ask you to press **Copy** first. Use the manual Copy flow if you want to review every title before it enters a chat.

## If something doesn't show up

- **No topics on a fresh install:** That's expected until there are usable records. Import the sample, check that **Mail** and **Imports** are on, and check the period. A topic may need more than one related record.
- **No matching topic:** Try a distinctive project name rather than a generic verb. In **Sources & Settings**, check which sources have records in the selected period. An imported mail or AI record needs both **Imports** and its record type enabled. An empty result only describes the current scope; it does not establish that the work never happened.
- **Import or source still looks empty:** Check the file format and the import status. Select the export file, not an unopened ZIP. Already imported records are skipped. Use **Reread Sources** after changing local files; it does not fetch newer mail or chats.
- **No window or Dock icon:** Horizon is a menu-bar app. Look for the calendar icon and click it. If the app never starts, check the Mac requirements and security warning before trying anything else.
- **Aside doesn't find references:** Try the same topic in Horizon first. If it works there, check the `~/Applications` app path, `node --version`, and the skill folder for the active Aside account. Try again in a new Aside chat with a named project. If lookup is unavailable, check those settings and whether any enabled source is readable and nonempty; if it reports no match, check the query and date range rather than assuming the work is missing.

### What a source switch does

The switches control **which records are eligible for the results**, not operating-system file access. Horizon can read the local feed files to build a snapshot before filtering by source and date. The optional Mail collection button is separate from importing a mailbox: it asks before accessing an already-running Mail app and may require macOS Automation permission. Collected subjects and dates can remain in local import files. Turning a source off hides it from results; it does not delete an import or revoke that permission.
