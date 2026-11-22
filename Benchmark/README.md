# Benchmark: tokens to a checked answer

> Historical 0.4.1 benchmark and fixtures. For the 0.5.0 to 0.5.1 comparison, see [current verification](../VERIFICATION.md).


Question: for the same fictional task, does the Horizon handoff use fewer tokens **through the final answer**, including retries, than pasting the entire topic's dated title list?

| Fictional task | Records | Full list | Horizon | Final answer |
|---|---:|---:|---:|---|
| Asterline: carton count + pickup day | 48 | 1,391 | 358 | Both correct: 48, Thursday |
| Bellwater: proof finish + quantity | 2 | 143 | 201 | Both correct: satin, 125 |
| Coralwick: an older exception | 30 | 2,631 | 1,598 | Both failed after retry: missed 17 units and February |
| Dunhaven: signature vs. legal review | 9 | 928 | 970 | Both failed after retry: correctly withheld signature confirmation but omitted the draft sent for legal review |

**Across the two tasks both arms completed correctly**, the full list used 1,534 tokens, Horizon 559 (63.6% fewer in aggregate). Most of this gain came from one 48-record task. On the two-record task, Horizon cost 58 more tokens (40.6% more). Across **all attempts**, including failures, the totals were 5,093 vs. 3,127 (38.6% fewer); both arms passed only 2/4 and made six model calls. Spending fewer tokens on a failed answer is not a successful saving. These figures are sums, not average percentage savings per person or task.

**What went wrong:** the short Coralwick packet omitted the older fact. It was in the full list and in the second-turn recovery list, but the model still did not extract it. For Dunhaven the relevant draft was present, but neither arm supplied the second required fact. Short packets do not eliminate the need to check sources.

## Reproduce

Use the bundled `cases.json` (exact English prompts), `results.json` (actual answers and per-call prompt/completion counts), `Benchmark.swift` (fixture generator), `protocol.txt` (scoring contract) and `run.mjs` (loopback-only model driver). No user records are included. Run on an Apple Silicon Mac with Swift and Node 18+:

```sh
swiftc -O Sources/Core.swift Benchmark/Benchmark.swift -o /tmp/horizon-benchmark
TZ=UTC /tmp/horizon-benchmark > /tmp/horizon-cases.json
# Start your own llama.cpp server; the benchmark makes requests only to localhost.
llama-server -m /path/to/qwen2.5-1.5b-instruct-q4_k_m.gguf --host 127.0.0.1 --port 18471 --device none --fit off --no-op-offload -ngl 0 -fa off -c 8192 -np 1 -t 6 --no-warmup
# In a second terminal:
node Benchmark/run.mjs /tmp/horizon-cases.json /tmp/horizon-results.json
```

Test runtime: [llama.cpp b12626](https://github.com/ggml-org/llama.cpp/releases/tag/b12626), [Qwen2.5-1.5B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/tree/91cad51170dc346986eccefdc2dd33a9da36ead9), Q4_K_M model file SHA-256 `6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e`. Temperature 0, seed 42, maximum 120 output tokens. Each arm starts a fresh chat. On a failed two-part answer, the driver retries once with the full title list and prior conversation. Counts are the model server's reported input and output tokens, including chat framing and replayed history. The model, weights and runtime are not distributed in the app.

**Limits:** Four constructed cases and one small local model, not a random sample of user work. The baseline is pasting all relevant metadata, not expert manual selection. Inputs are titles, not message or document bodies; no optional coverage warnings were supplied to the isolated exporter. Actual windows can add them. This does not measure people’s time, paid API bills, cached-token discounts, or ChatGPT/Claude/OpenClaw performance. No external model integration or tokens are needed for Horizon itself to prepare the handoff.
