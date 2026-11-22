# Getting started with Contexta Horizon

Horizon prepares a short, dated list of references for a task you want to resume. It does not write the answer, upload your sources, or talk to an AI service.

## Install

1. Download **Contexta-Horizon-0.4.1-macOS-arm64.zip** from the [Horizon release](https://github.com/AgentChiChi/contexta-horizon/releases/tag/v0.4.1). The prebuilt app requires an Apple Silicon Mac and targets macOS 13 or later. Intel and older macOS versions have not been verified.
2. To check the download, run `shasum -a 256 Contexta-Horizon-0.4.1-macOS-arm64.zip` and compare it to `SHA256SUMS.txt` on the release page.
3. Unzip the archive, move `contexta-horizon.app` to Applications, then open it. If upgrading Horizon, quit the old copy and replace that same app.
4. The preview is ad-hoc signed, **not Apple-notarized**. macOS may block it. Do not disable Gatekeeper. If you do not trust the download, stop or inspect and build the attached source instead.

## Use it

1. Click the calendar icon in the menu bar. Type a short task that names a project, such as **Review the Harborline quote**, or click a suggested topic.
2. Read the inline preview. Each reference shows a date, source type and title. An inferred link is not proof that an action happened. Click **Copy** only if the preview is appropriate to share. Pressing Return does not copy.
3. Paste into your chosen chat or document yourself. The clipboard contains text, **not attached files or full email bodies**. If your question depends on a price inside a spreadsheet or a clause inside a contract, open the source and deliberately supply the relevant passage. People and project names in titles can remain visible.

## Getting your first result

A clean install does **not** discover your AI accounts, download Gmail, scan your entire disk, or create a general-purpose file index. With no usable records, no answer is the correct result. Open **Sources & Settings → Import…** to import a supported local ChatGPT/Claude export or an `.mbox` snapshot. Reloading local data is not a live Gmail sync. File results require a compatible local WorkIndex file list. More than one related record can be necessary to form a topic; try a distinctive project name rather than a generic verb.

The default period is the last three calendar months. Use **Sources & Settings** for six months, a custom range within six months, or to exclude a source type. If a fresh import appears empty, check its dates, source switches and whether it contains a repeated project name. When you change a source, review the preview again before copying.

## What the demo and tests cover

The [walkthrough](https://github.com/AgentChiChi/contexta-horizon/blob/v0.4.1/Horizon-Walkthrough.mp4) uses actual native app views with fictional data and English captions. It is not a live AI exchange. Read **VERIFICATION.md** for exact tested behavior, the full-task token benchmark and its limitations. No private indexes, accounts, emails or model weights are included in the app.

### Try it without exposing any personal records

Download [Harborline-Demo.mbox](https://github.com/AgentChiChi/contexta-horizon/releases/download/v0.4.1/Harborline-Demo.mbox). In **Sources & Settings → Import…**, select the mailbox, confirm the import, then click **‹ Simple View**. Type **Harborline quote**. The prepared demo has three fictional mail records; the video uses a separate fixture that also has file and AI references.

The downloadable sample is dated around the release. If it has aged out of the current period, use a custom period covering **November 19–21, 2026**, or make a fresh sample with `bash Demo/make-sample.sh > /tmp/Harborline-today.mbox` from the extracted source ZIP. Import the new file. No personal mail account is needed.
