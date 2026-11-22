# Verifying Horizon 0.5.2 (build 8)

**Question:** When a user limits which records a new lookup may read, does Horizon enforce the limit before opening files? Can someone try a realistic preview without importing anything?

All cases below use synthetic records. For the direct comparison, 0.5.1 and 0.5.2 were observed at the reader's metadata-check, file-open and imports-directory boundaries. These are instrumented code-boundary observations, not a claim that every OS system call was traced.

| New lookup scenario | 0.5.1 | 0.5.2 |
|---|---|---|
| Every source off | Checked and opened all three fixture feeds, a mixed import and the manifest, then returned unavailable | No feed or manifest checked/opened; no imports-folder check or listing; returned unavailable |
| Only AI chats on | Opened the same set before filtering | Opened only the AI feed and collection manifest |
| All sources on | Returned the matching fictional topic | Returned the matching fictional topic |

[Baseline observations](Evaluation/0.5.2/baseline-matrix.json) · [All 16 current combinations](Evaluation/0.5.2/final-matrix.json)

- **All 16 on/off combinations:** the dedicated source-file checks followed their switches. Imports could mix chat and mail, so only the two combinations with AI, Mail and Imports on enumerated that directory (Files may be either on or off).
- **81 transitions** from a set of enabled sources to a subset, including unchanged sets: restricted cached evidence IDs exactly matched a fresh read. A dashboard race test also checked that stale results did not reappear.
- **32 headless queries** on the installed, uninstrumented build: one fixture query and one demo-only query for each combination. No fictional demo content appeared, and the original fixture files were unchanged.
- **Native UI:** empty window → enter labeled example → inspect file, AI and mail titles → exit. No source file, stored preference or clipboard changes in this check. The button was hidden on a nonempty query and in a populated workspace. Copy remained disabled in the demo.
- **Release checks:** 62/62 synthetic self-tests, 18/18 static checks, fictional mailbox import passed, and the native-window flow passed. The application ZIP was unpacked, ad-hoc signature verified, and its executable matched the tested installation byte for byte.

### Reproduce locally

From the repository root with Swift and Node installed:

```sh
bash build.sh
PROBE=$(mktemp -d)
node Evaluation/0.5.2/instrument.cjs . "$PROBE"
node Evaluation/0.5.2/matrix.cjs "$PROBE/probe" final
node Evaluation/0.5.2/installed-matrix.cjs "$PWD/dist/contexta-horizon.app/Contents/MacOS/ContextaHorizon"
```

The probe is a separate test executable; the shipped app does not have that extra instrumentation. The scripts create temporary fictional homes, not live-account tests. [Cached/fresh comparison](Evaluation/0.5.2/Parity.swift).

### What this doesn't establish

A switch governs **new lookups**, not OS permissions, deletion, or explicit actions such as importing a file. A read already in flight uses the switches captured at its start; its output is restricted again before display. A title can still be sensitive. The standalone app doesn't call an AI provider. A manual paste or an optional Aside lookup can put titles into a hosted chat.

No new model benchmark is claimed. All four synthetic benchmark handoffs were byte-identical to 0.5.1. The [earlier measurement](https://github.com/AgentChiChi/contexta-horizon/blob/v0.5.1/VERIFICATION.md) found 10/10 target references in six held-out cases but only 2/4 correct final answers on a separate four-task local-model benchmark. This update tests control over sources, not stronger reasoning, lower provider bills or real-user time savings.
