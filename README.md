# Contexta Horizon for Mac

## Where did we leave this?

On Friday, you revised a supplier quote. On Monday, you can still find the spreadsheet. What you can’t remember is whether the supplier confirmed the sample delivery date or whether you meant to ask on the next call.

That’s where **Contexta Horizon** starts. In the fictional Harborline walkthrough, you type **“Follow up on the Harborline quote.”** The preview brings a workbook named *Harborline quote v2.xlsx* back alongside an earlier AI conversation about the supplier call and an email titled *Harborline quote: confirm the sample delivery date*. You can see when each record appeared and where it came from. The email title tells you which thread to check; it doesn’t tell you the supplier said yes.

Now you know what to do next: open that thread before promising a date. Or, if you want help drafting the follow-up, copy the references into the chat you use today. It doesn’t have to be the one you used on Friday.

**0.4.1 English preview** · Apple Silicon · macOS 13+ deployment target · ad-hoc signed, not Apple-notarized.

- [Download the Mac app](https://github.com/zakat9/contexta-horizon/releases/download/v0.4.1/Contexta-Horizon-0.4.1-macOS-arm64.zip)
- [Watch the English walkthrough (MP4)](https://github.com/zakat9/contexta-horizon/blob/v0.4.1/Horizon-Walkthrough.mp4)
- [Read the setup and usage guide](https://github.com/zakat9/contexta-horizon/blob/v0.4.1/GUIDE.md)
- [Read the verification report](https://github.com/zakat9/contexta-horizon/blob/v0.4.1/VERIFICATION.md)
- [Source code](Sources/) · [Reproducible benchmark](Benchmark/) · [Fictional sample](Demo/Harborline-Demo.mbox)
- [Release notes and checksums](https://github.com/zakat9/contexta-horizon/releases/tag/v0.4.1)

### What Horizon keeps in view

Horizon works on your Mac with the local records you make available: file listings, AI conversation metadata and mail snapshots. It starts with the last three months. You can narrow the dates around a call, look back up to six months, or leave a source out. References keep their dates and source types, and inferred connections are marked. A file’s name is not its contents; a draft is not a decision.

You see the exact text before you copy it. Nothing is sent to an AI service automatically, and the original files and messages stay where they are.

### What we verified

The release passed 40/40 synthetic app tests and 15/15 static checks. We also checked the native window flow, an empty-profile import and the downloadable ZIP.

A shorter handoff can save tokens, but not always: on a 48-record task, both answers were correct and Horizon used 358 tokens instead of 1,391; on a two-record task, it used 201 instead of 143. Both approaches passed only two of four fictional tasks. The [full report](https://github.com/zakat9/contexta-horizon/blob/v0.4.1/VERIFICATION.md) includes the failures, retries and limits of this local-model test.

## Build from source

Install Apple Command Line Tools, then run `bash build.sh` from the repository root. The app is written to `dist/contexta-horizon.app`; the script does not install the app or fetch user data. See [the benchmark protocol](Benchmark/README.md) for the separate local-model test.

No open-source license has been granted.
