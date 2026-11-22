# Getting started with Contexta Horizon

**Public preview v0.5.2 (build 8)** · Apple Silicon · macOS 13 or later

Contexta Horizon helps you pick up earlier work by finding a short list of dated references on your Mac. It shows titles and where they came from, not an AI-generated answer. Start with the built-in fictional example. Then, if you want to try your own work, choose what to import and review exactly what you'd share.

## Install or upgrade

1. Open the [v0.5.2 release](https://github.com/AgentChiChi/contexta-horizon/releases/tag/v0.5.2) in `AgentChiChi/contexta-horizon`. Download [Contexta-Horizon-0.5.2-macOS-arm64.zip](https://github.com/AgentChiChi/contexta-horizon/releases/download/v0.5.2/Contexta-Horizon-0.5.2-macOS-arm64.zip) and [SHA256SUMS.txt](https://github.com/AgentChiChi/contexta-horizon/releases/download/v0.5.2/SHA256SUMS.txt). The prebuilt app does not run on Intel Macs. From the download folder, run `shasum -a 256 Contexta-Horizon-0.5.2-macOS-arm64.zip` and compare the output with the corresponding line in `SHA256SUMS.txt`. Use the same check for the sample mailbox or skill ZIP if you download them. If a hash differs, don't open the file.
2. Unzip the archive in Finder and move `contexta-horizon.app` to **Applications**. If you want the optional Aside skill, use **Applications** inside your home folder (`~/Applications`), creating the folder if needed. The helper does not look in `/Applications`. Open the app; its calendar icon appears in the menu bar.
3. **Upgrading?** Right-click the calendar icon, choose **Quit Contexta Horizon**, and replace the old app bundle before opening the new one. Keep only one installed copy. Replacing the app does not remove imports stored separately under `~/WorkIndex`.

**macOS security:** The app is ad-hoc signed and **not Apple-notarized**. A matching checksum verifies the download against the release's checksum; it is not notarization. If macOS blocks the app, verify the source and leave the app unopened if your Mac's security policy does not allow it. Do not disable Gatekeeper or bypass the warning. If appropriate, review and build the source locally: with Apple's Command Line Tools installed, run `bash build.sh` from the extracted release source. It builds `dist/contexta-horizon.app`, generates the sample mailbox, and runs checks without installing the app.

## Start with the fictional example

When Horizon has finished reading sources and there are no topics and nothing typed, click **Try a fictional example**. You'll see a made-up Harborline topic with dated file, chat, and mail titles in the same preview format as a real result. Opening the example doesn't read any source files or save or import anything. **Copy** is disabled. Click **Exit example** to return to the empty view. The example is not offered for a typed task with no match, and Aside lookup never returns it.

## Use your own records and share a reviewed copy

1. In **Sources & Settings → Import…**, select an export you want Horizon to use: an extracted ChatGPT or Claude `conversations.json`, an Apple Mail or Gmail Takeout `.mbox`, or a compatible normalized `.jsonl`. Imports are local snapshots, not live connections. File references come from a compatible local WorkIndex file list; Horizon doesn't crawl your disk or discover accounts.
2. Return to **Simple View**. Type a short task with a distinctive project name, or pick a suggested topic. Review the exact preview, including any source cautions. Dates are record dates, and a title about a revised quote doesn't prove the revision was accepted. Check the original when you need a price, clause, or confirmed decision.
3. Click **Copy** only when you're happy with the preview. Pressing Return never copies. Paste the plain text yourself into the ChatGPT or Claude conversation you choose. You can also paste it into Aside without installing a skill. The copy does not contain attachments or full document or message bodies. Add an excerpt separately only if you mean to share it.

**Privacy:** Horizon processes records locally and does not call an AI service or upload the preview. Its results use file listing metadata, chat titles and timestamps, and mail subjects and dates. Mail imports don't retain message bodies or sender and recipient addresses as records; chat imports don't retain conversation text. A title can still reveal a person, project, or sensitive subject. Once you paste the preview into a chat, that provider's processing, storage, and privacy rules apply.

## Optional: practice with a sample mailbox

Unlike the built-in example, the [sample-mail.mbox](https://github.com/AgentChiChi/contexta-horizon/releases/download/v0.5.2/sample-mail.mbox) download is a real import of **fictional** data. It contains 11 made-up messages about Harborline, Atlas, and Northfield. In **Sources & Settings → Import…**, select the mailbox. Keep **Imports**, **AI chats**, and **Mail** on to see the imported records. Go back to **Simple View**, choose **Harborline** or type **Follow up on the Harborline quote**, and review and copy the preview as you would with your own records.

The default period is the last **3 calendar months**. If the sample is older, choose **6 months** or a **Custom** range of up to six months that covers its dates. You can also download and unzip **Source code (zip)** from the release, open Terminal in the extracted source folder, and make a fresh mailbox:

```bash
bash Examples/make-sample.sh "$HOME/Downloads/sample-mail-today.mbox"
```

This writes 11 fictional messages dated 2 to 24 days before you run it. It does not read your personal records or send anything. Reimporting the same records skips duplicates; importing a newly dated copy can add records. To remove the downloaded sample, delete only its import file ending in `-sample-mail.jsonl` from `~/WorkIndex/horizon-v1/imports/`, then click **Reread Sources**. A sample imported under a different filename will have a different suffix.

## What a source switch does

The switches control what Horizon opens during a source read, not just what it displays. The app and the optional Aside lookup use the same saved settings.

- **Files**, **AI chats**, and **Mail** each control a separate local feed. When a switch is off, its feed isn't checked, opened, or read. The manifest that records when these feeds were collected is read only while at least one of the three is on.
- The imports folder isn't checked, listed, or opened unless **Imports**, **AI chats**, and **Mail** are **all on**, even if the only thing you imported was mail. **Files** is not required. Import files can mix chat and mail records, so Horizon skips the entire folder if any of those three switches is off. If **Imports** is on but **AI chats** or **Mail** is off, the Imports row says **Skipped, not opened**. If **Imports** itself is off, the row says **Off**. **Nothing imported yet** means Horizon did check the folder and found it absent or empty.
- With all four switches off, a normal source read opens no source file, not even the manifest, and Aside lookup returns unavailable.
- Turning a switch off removes the excluded records from the active view without starting a new read. It doesn't cancel a read already under way: that read uses the switches captured at its start, and any excluded records are discarded before it updates the view. Turning a switch on makes newly allowed sources eligible for a read.

**Manual actions are different.** You can still use **Import…** or **Collect from Mail…** while the switches are off. These actions can check existing import files for duplicates and save new snapshots; the results stay out of the view until all three import switches are on. **Collect from Mail…** is separate from importing a mailbox export: it asks for confirmation, accesses only an already-running Apple Mail app, and may trigger a macOS Automation permission prompt. It collects recent subjects and dates from Inbox and Sent, not bodies or addresses, and sends nothing. Switching a source off doesn't delete saved imports or revoke Automation permission.

## Optional: let Aside find earlier work

Install the skill only if you want Aside to retrieve local references on request. The reviewed **Copy** flow doesn't need the skill or Node.js.

1. Put Contexta Horizon v0.5.2 at `~/Applications/contexta-horizon.app`. Run `node --version` in Terminal. If Node.js is missing, install a supported Node.js LTS release and run the check again.
2. Download and unzip [Horizon-Aside-skill.zip](https://github.com/AgentChiChi/contexta-horizon/releases/download/v0.5.2/Horizon-Aside-skill.zip). Copy the entire `horizon-resume` folder into `skills/user` under your active Aside account's root. The installed path should be `<Aside account root>/skills/user/horizon-resume/SKILL.md`, with `scripts/lookup.mjs` inside `horizon-resume` and no extra folder from the archive. Open a new Aside chat. To check installation without looking up records, ask if the `horizon-resume` skill is available.
3. Ask **“Where did we leave the Harborline quote?”** (this example needs the sample mailbox, not just the built-in example). No wake word or command is required. **“Let's revisit that quote”** can work if the current chat identifies the project. If the chat already has the answer, Aside uses it. If the project is unclear, Aside asks which one you mean. A bare **“try again”** or a web search doesn't trigger lookup. Say **“Use only this chat”** to rule it out.

The skill sends a short topic query to the local app, which uses the saved period and source switches. If it finds a match, dated reference text enters the **current Aside chat** and may be processed by its model. You aren't asked to press **Copy** first. Use the manual Copy flow if you want to review each title before it enters a chat. See the [Aside integration README](Integrations/Aside/README.md) for more details.

## Troubleshooting

- **No window or Dock icon:** Horizon is a menu-bar app. Click the calendar icon to open Simple View. If the app doesn't start, check the Mac requirements and any macOS security warning first.
- **No topics or no match:** On a fresh install, try the built-in example before typing. For your own records, use a distinctive project name and check the date range and coverage in **Sources & Settings**. An inferred topic may need more than one related record. An empty result means no match in the current scope, not that the work never happened.
- **An import succeeded but isn't visible:** Check that **Imports**, **AI chats**, and **Mail** are all on and that the record dates fall in the selected period. If importing failed, choose the extracted export, not the unopened ZIP, and check the import status. Records already imported won't be added again. **Reread Sources** rereads eligible local sources; it doesn't fetch new mail or chats.
- **Collect from Mail didn't run:** Open Apple Mail yourself and try again if you want to allow access. If you declined the macOS Automation prompt, review **System Settings → Privacy & Security → Automation**. Alternatively, import an `.mbox` export manually without granting Automation permission.
- **Aside didn't find references:** Try the same named project in Horizon first. If it works there, check `~/Applications/contexta-horizon.app`, `node --version`, and the skill path for the active Aside account, then try in a new chat. If lookup is unavailable, check whether any enabled source is readable and nonempty. If it reports no match, check the topic and date range.
