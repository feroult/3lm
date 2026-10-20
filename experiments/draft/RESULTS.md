# Speculative decoding on the hybrid Qwen3.8-27B (RTX 5070 Ti, 32k ctx, -ngl 55, -t 12, q8 KV)

> Helper scripts live in this folder; the raw outputs (`res_*.txt`) were removed from the repository and can be regenerated with `bench_one.sh`.

Baseline measured in the same session: 15.1 t/s (VRAM 14.1GB). Vocabulary: all candidates have tokens/merges/token_type IDENTICAL to the 27B's (hash 6d8afc30d32560a9 / b645cd089105aa7f / 4e54056be99c97dd).

| Config | Gen t/s | Acceptance | Total VRAM |
|---|---|---|---|
| baseline | 15.1 | - | 14.1GB |
| draft Qwen3.5-0.8B Q8, n-max 4 | 10.0 | 33% | 15.1GB |
| draft Qwen3.5-0.8B Q8, target ngl 51 (VRAM matched) | 8.2 | 32% | 14.3GB |
| draft Qwen3.5-2B Q4_K_M, n-max 3 | 10.6 | 39% | 15.5GB |
| draft Qwen3.8-2B-Distill Q4_K_M, n-max 3 | 3.9 (VRAM overflow?) | 40% | 15.5GB |
| ngram-mod (default), from-scratch generation | 15.6 | 11% | 13.7GB |
| ngram-mod n-min 8 n-max 32 n-match 8, from-scratch generation | 16.4 | 22% | 13.7GB |
| CODE EDIT: baseline | 15.5 | - | 13.7GB |
| CODE EDIT: ngram-map-k (n 8, m 8, hits 1) | 20.7 (30.9 + 15.5) | 95% where it triggered | 13.7GB |
| CODE EDIT: ngram-mod n-min 8 n-max 32 n-match 8 | 36.9 (42.8 + 32.3) | 56% | 13.7GB |

Takeaways: small draft models make the hybrid (partly CPU-offloaded) 27B slower; n-gram speculation (no extra model, no extra VRAM)
more than doubles generation when the output repeats the context (code edits) and costs nothing on from-scratch generation.
The same n-gram settings did **not** help the MoE Qwen3.6-35B-A3B (see `docs/BENCHMARKS.md`).
