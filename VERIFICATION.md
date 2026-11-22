# What changed, and what the tests actually show

**Contexta Horizon 0.5.1 (build 7)** · Apple Silicon local preview, ad-hoc signed, not notarized. All inputs below are fictional. We measured the app's retrieval separately from a model's ability to use what it received.

| Measure | 0.5.0 | 0.5.1 |
|---|---:|---:|
| Target facts present in selected titles, four development tasks | 6/8 | 8/8 |
| Target references in six separately held-out English/Korean cases | 9/10 | 10/10 |
| Correct final answers, four development tasks, Qwen2.5-1.5B-Instruct | 2/4 | 2/4 |
| Model calls across those tasks, including retries | 6 | 6 |
| Total input + output tokens across the four tasks | 3,127 | 3,119 |
| Two-record task, tokens through correct answer | 201 | 171 |

**The comparison is with Horizon 0.5.0, not with ChatGPT or Claude.** Pasting the full list on the two-record task cost only 143 tokens. Identical model inputs reused their measured result; changed inputs used the same local model, temperature, seed and retry policy. [Per-round results and actual answers](Evaluation/0.5.1/rounds.json) · [Model and scoring protocol](Benchmark/README.md).

### Three changes, three checks

1. **Short handoffs:** remove repetitive headings on most small results; retain dates, types and warnings. With one Korean meeting question, compaction led the model to invent a time. Restoring the original small timing layout restored abstention on that case. This is not a general hallucination fix.
2. **Diverse citations:** choose among reply and revision chains instead of blindly filling six places with recent variations. The 30-row Coralwick packet recovered the title containing the 17-unit limit and February review. The model still failed the two-part answer after a retry.
3. **Status and corrections:** distinguish substantive holds and constraints from routine mentions. A targeted English/Korean stress probe recovered 4/4 requested status references versus 0/4 after round two. That probe informed the fix; it is **not** part of the held-out score. Distinct evidence with reused source-local IDs is preserved (6/6 in the collision regression).

### Native checks

- 58/58 synthetic self-tests, 16/16 static checks; the example mailbox imports on an empty profile.
- Native window smoke: type, inspect, change topics, no match, change period, return. No clipboard write during the smoke run.
- Independent synthetic fixture: the visible native preview matched the actual headless result byte for byte. The optional Aside helper uses that command, not a separate summarizer.
- Distribution: arm64 executable, ad-hoc signature; the unpacked public ZIP verified locally. SHA-256 digests accompany the release.

**Limits:** one small model, constructed cases, titles rather than document bodies. Another probe still produced an unsupported conclusion about a signature. A missing confirmation is not evidence of non-signature. These experiments do not measure real-user time, API bills or provider-model accuracy. [Earlier 0.4.1 report](https://github.com/AgentChiChi/contexta-horizon/blob/v0.4.1/VERIFICATION.md).

The distributable is the previously verified app, not a new unsigned recompile. Its built-in self-test contains fictional redaction fixtures; a binary string scan therefore finds **synthetic** paths and addresses. The release ZIP was rebuilt from an allowlist (executable, Info.plist, signature) to exclude macOS extended-attribute sidecars. These checks do not imply Apple notarization or Gatekeeper approval.
