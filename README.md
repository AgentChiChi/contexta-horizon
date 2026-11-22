# Contexta Horizon for Mac

**New chat. Same project.** Pick up the thread in ChatGPT, Claude or Aside without pasting your entire history. Horizon brings dated references from your local file lists, earlier AI chats and mail into one Mac menu bar preview. You decide which conversation gets them.

**[Download for Apple Silicon](https://github.com/AgentChiChi/contexta-horizon/releases/download/v0.5.2/Contexta-Horizon-0.5.2-macOS-arm64.zip)** · [Get started](GUIDE.md) · [0.5.2 release](https://github.com/AgentChiChi/contexta-horizon/releases/tag/v0.5.2)

macOS 13+ · Apple Silicon · **Public preview, ad-hoc signed and not Apple-notarized.** If your Mac blocks it, leave Gatekeeper enabled. See the [installation guide](GUIDE.md).

**Watch: New chat. Same project.** (39 seconds, sound off)

https://github.com/user-attachments/assets/4b900293-a088-4993-8a61-5ab2aa388ffa

[Download the MP4](https://raw.githubusercontent.com/AgentChiChi/contexta-horizon/main/docs/media/Horizon-0.5.2-Walkthrough.mp4) · [Try the fictional mailbox shown in the video](https://github.com/AgentChiChi/contexta-horizon/blob/v0.5.2/Demo/Harborline-Demo.mbox)

## “Did they approve the quote, or did we only send a draft?”

Your new chat hasn't seen Friday's work. You could paste the whole thread, or give it the clues that matter: a workbook called *Harborline Q3 quote.xlsx*, an earlier chat titled *Harborline quote review notes*, and a mail subject that says *Harborline contract draft for review*. That last title is a reason to **check the reply**, not a reason to tell a customer the deal is signed.

Horizon shows you the dates and source types. It doesn't read a contract and decide what happened. That's what makes the preview useful even if you never open an AI chat.

## Try it before sharing anything

1. Open Horizon on a fresh install. In the empty view with nothing typed, choose **Try a fictional example**. No sign-in, mailbox import or model needed for the demo.
2. Inspect the Harborline references, then choose **Exit example**. The demo lives in memory. **Copy is off**, and the example doesn't become one of your projects.
3. To try the actual handoff without personal data, import the [fictional mailbox](https://github.com/AgentChiChi/contexta-horizon/releases/download/v0.5.2/sample-mail.mbox) from **Sources & Settings → Import…**. Return to the simple view and type **“Follow up on the Harborline quote.”**

### Two ways to resume work

**ChatGPT or Claude:** Review the real or imported references, click **Copy**, then paste them into the chat you choose. A useful next prompt:

> Using only these dated titles, tell me what was last documented, what is still unknown, and which record I should open before replying. Cite the title and date. Don't treat a request as confirmation.

**Aside:** With the [optional account skill](Integrations/Aside/), ask **“Where did we leave the Harborline quote?”** There's no wake word. If a local lookup is needed, the references enter your current Aside chat and may be processed by its model. Use the manual Copy route if you want to inspect every title first.

## What changes when you turn a source off?

In 0.5.1, switching a source off filtered the result after the feeds were read. In **0.5.2**, a new lookup doesn't open a disabled file, chat or mail feed. Imports may mix chat and mail records, so the entire imports folder is skipped unless **Imports, AI chats and Mail** are all on. Skipped doesn't mean empty. Explicit imports and Mail collection are separate actions. [Details and limits](GUIDE.md#what-a-source-switch-does)

## What we tested

- **16 switch combinations:** with every source off, no source file was checked or opened and the imports directory wasn't listed. With only AI on, the reader opened the AI feed and the shared collection manifest, not the file or mail feeds.
- **81 switch-off transitions:** cached evidence matched a fresh read every time. Previously loaded mixed imports didn't linger in the results.
- **32 queries against the installed app:** fictional demo records never appeared in a lookup. Opening and exiting the demo changed no fixture files, preferences or clipboard in the native-window test.

These are **source-control and isolation tests**, not model accuracy scores. The four earlier benchmark handoffs stayed byte-identical. In the earlier local-model run, correct final answers were **2 of 4**; we do not claim that 0.5.2 improves that score or reduces your API bill. [Verification and reproducible checks](VERIFICATION.md)

### Build from source

With Apple Command Line Tools installed, run `bash build.sh` from the repository root. The script builds `dist/contexta-horizon.app` and runs synthetic checks; it doesn't install the app. No open-source license has been granted.
