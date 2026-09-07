**SuperSamuel model research — 7 September 2026**

Follow-up: the user chose to try Gemma after this research. Version 1.3.7 implements that choice; see [README.md](README.md) and [VALIDATION.md](VALIDATION.md) for current behavior and the synthetic API checks. The comparison below describes the pre-switch baseline.

My recommendation is to keep the current speech recognition pipeline, retain Gemini 3.8 Flash as the cleanup baseline, and test Gemma 4 31B on OpenRouter's Cerebras route first. GPT-OSS 120B on Cerebras deserves the same trial. A smaller model is a credible fit for this narrow editing task; there is not yet evidence that either candidate preserves our transcripts well enough to become the default. Gemini 3.5 Flash-Lite and GPT-5.6 Luna complete a useful five-model comparison.

This is source research and a review of the repository at `bae658a`, not an inference benchmark. No paid generations were run and no private recordings or transcripts were uploaded. Prices and provider statistics below are observations from September 7, not commitments about future performance. Public API responses and selected provider pages were saved under `.context/model-research/` for reproducibility.

**What we actually need the model to do.** The app has three separate stages:

| Stage | Repository default | Implication for model selection |
| --- | --- | --- |
| Live speech recognition | Direct OpenAI `gpt-live-transcribe` | Requires streaming audio transcription. A fast text model cannot replace this endpoint. |
| Saved-audio fallback | OpenRouter `openai/gpt-transcribe` | Requires a speech-to-text endpoint and audio support. |
| Optional cleanup after Stop | OpenRouter `google/gemini-3.8-flash` | Receives the transcript and editing prompt, with no audio or screenshot. This is where the proposed models compete. |

These are code defaults, not an inspection of the installed app's saved preferences. Cleanup is off by default. The actual Settings default is Gemini 3.8 Flash, despite an older `defaultCleanupModel` constant elsewhere naming GPT-5.4 Nano. Sources: [SettingsStore.swift](app/Sources/SuperSamuelApp/SettingsStore.swift), [OpenRouterService.swift](app/Sources/SuperSamuelApp/OpenRouterService.swift), [RealtimeTranscriptionService.swift](app/Sources/SuperSamuelApp/RealtimeTranscriptionService.swift).

The cleanup prompt demands minimal edits: remove clear disfluencies, resolve explicit self-corrections, preserve uncertainty and emphasis, retain every distinct idea, keep technical names and numbers, preserve the language mixture, and never answer questions embedded in the transcript. This is a constrained editing problem. It does not require a large knowledge base, coding agents, tools, or advanced mathematical reasoning. But mistakes such as deleting a negation are much more consequential than a missed comma. Source: the full prompt in [OpenRouterService.swift](app/Sources/SuperSamuelApp/OpenRouterService.swift).

Keeping recognition separate also preserves the benefit of transcribing while the user speaks. OpenAI's current documentation recommends `gpt-live-transcribe` for this workflow. It says delay settings trade earlier text against additional audio context, and warns against inferring fixed timing from their names. There is no evidence in this research that replacing that stage would improve SuperSamuel. [OpenAI realtime transcription](https://developers.openai.com/api/docs/guides/realtime-transcription).

**The Gemma model is real, and 31B is not automatically too small.** Its exact OpenRouter ID is `google/gemma-4-31b-it`. It is Gemma 4, not Gemma 3 27B. Google's model card lists a 30.7-billion-parameter dense model, native system messages, text/image input, and a 256K model context. The 31B variant has no audio encoder. The Cerebras endpoint currently exposed through OpenRouter limits context to 131,072 tokens. Both context sizes are ample for ordinary dictation. [Google model card](https://ai.google.dev/gemma/docs/core/model_card_4), [OpenRouter endpoint API](https://openrouter.ai/api/v1/models/google/gemma-4-31b-it/endpoints).

Google's technical report gives Gemma 4 31B scores of 98.9 on IFEval and 76.0 on IFBench, compared with 90.4 and 32.0 for Gemma 3 27B. These are useful instruction-following signals. However, the table explicitly reports Gemma 4 in **thinking mode**. They cannot establish the quality of the faster configuration with thinking disabled, and neither benchmark measures our exact transcript cleanup behavior. My inference is that Gemma is capable enough to warrant a serious trial, not that it has already demonstrated parity with Gemini. [Gemma 4 technical report, Table 5](https://arxiv.org/html/2607.02770v1#S2.T5).

Parameter counts alone are also misleading across architectures: GPT-OSS 120B is a mixture-of-experts model with roughly 5.1B active parameters per pass, whereas Gemma 31B is dense. The larger number in the name does not translate directly into slower generation or better editing. [GPT-OSS model description](https://openrouter.ai/openai/gpt-oss-120b).

**There is an important Cerebras availability distinction.** Cerebras says it removed Gemma 4 31B from its direct public endpoints on September 3, 2026, while retaining dedicated deployments. However, OpenRouter's current endpoint API still lists `cerebras/fp16` for Gemma, with status `0`, 100% reported uptime over the sampled 30-minute window, and approximately 99.996% over the preceding day. OpenRouter's model page also displays recent speed statistics. This supports treating it as an OpenRouter candidate; it does not prove that a direct Cerebras account can use it, nor does metadata prove a successful inference request. The reason the two offerings differ is unverified. [Cerebras deprecations](https://inference-docs.cerebras.ai/support/deprecation), [OpenRouter Gemma endpoints](https://openrouter.ai/api/v1/models/google/gemma-4-31b-it/endpoints).

**Current provider observations.** Prices are USD per million text tokens at the named endpoint. Speed and startup figures are OpenRouter's displayed P50 statistics from mixed traffic, not the same prompts run against every model. The table is a shortlist for testing, not an accuracy or end-to-end latency ranking.

| Model and provider | Input / output $ per 1M | Displayed output tok/s | Displayed latency | Why test it |
| --- | ---: | ---: | ---: | --- |
| [Gemini 3.8 Flash — Google AI Studio Priority](https://openrouter.ai/google/gemini-3.8-flash) | 1.35 / 6.75 | 219 | 2.76 s | Current app preference; retain as the baseline. |
| [Gemma 4 31B — Cerebras](https://openrouter.ai/google/gemma-4-31b-it) | 0.99 / 1.49 | 495 | 0.26 s | First candidate for faster cleanup with thinking disabled. |
| [GPT-OSS 120B — Cerebras](https://openrouter.ai/openai/gpt-oss-120b) | 0.35 / 0.75 | 873 | 0.21 s | Strong speed/cost candidate; use low reasoning and measure its overhead. |
| [Gemini 3.5 Flash-Lite — Google AI Studio](https://openrouter.ai/google/gemini-3.5-flash-lite) | 0.30 / 2.50 | 64 | 0.66 s | Simple Google alternative, especially worth checking on short transcripts. |
| [GPT-5.6 Luna — OpenAI](https://openrouter.ai/openai/gpt-5.6-luna) | 0.20 / 1.20 | 84 | 1.40 s | Inexpensive current OpenAI option with reasoning disabled. |

The observations visibly change: a separate reading of the Gemma page during this research showed 457 tok/s and 0.30 s. Describing it as approximately 500 tok/s is reasonable. Treating 495 as a reproducible application measurement would not be.

Gemini 3.8 prices currently include an advertised 50% discount. Its standard AI Studio endpoint was $0.75/$3.75, versus $1.35/$6.75 for the Priority endpoint the app prefers. The undiscounted prices shown were $1.50/$7.50 and $2.70/$13.50 respectively. Do not compare a model's cheapest headline price with a different provider's fastest speed. [Gemini endpoint pricing](https://openrouter.ai/api/v1/models/google/gemini-3.8-flash/endpoints).

Likewise, Google reports 350 tok/s for Flash-Lite in Artificial Analysis testing; our OpenRouter page snapshot showed 64 on AI Studio and 186 on Vertex EU. Cerebras advertises substantially higher Gemma throughput than the roughly 500 seen through OpenRouter. These are different traffic samples and configurations, not interchangeable measurements. [Google Flash-Lite announcement](https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-3-6-flash-3-5-flash-lite-3-5-flash-cyber/), [Cerebras Gemma announcement](https://www.cerebras.ai/blog/gemma-4-on-cerebras-the-fastest-inference-is-now-multimodal).

**Why tokens per second matter, but do not decide this.** The user waits for the complete edited transcript. The app currently makes a non-streaming cleanup request after transcription completes, then saves and archives the result before delivery. Faster generation can therefore reduce the wait substantially on longer dictation. Sources: [OpenRouterService.swift](app/Sources/SuperSamuelApp/OpenRouterService.swift), [RecordingProcessor.swift](app/Sources/SuperSamuelApp/RecordingProcessor.swift).

The useful decomposition is:

```text
Stop to paste = remaining transcription time
              + cleanup request/network/queue/prompt processing
              + any reasoning before the answer
              + generation of the complete cleaned transcript
              + local save/archive/paste work
```

For illustration only, generation of 500 output tokens takes 5 seconds at 100 tok/s, 1 second at 500 tok/s, and 0.57 seconds at 873 tok/s. With just 50 output tokens, those generation times are 0.50, 0.10, and 0.057 seconds: request startup can dominate. These are arithmetic examples that exclude startup and reasoning, not predictions for SuperSamuel. OpenRouter documents the distinction between time to first token and generation throughput. [OpenRouter latency guide](https://openrouter.ai/docs/guides/best-practices/latency-and-performance).

Measure time to the first **visible answer** separately from time to the first event or reasoning token. If reasoning is already included in that measured startup time, do not add it twice. Different tokenizers also emit different token counts for the same transcript; compare completion time on the same text, not just token rates. Streaming could improve progress feedback, but merely showing the first words earlier would not make a complete, correct paste happen earlier.

**Reasoning settings materially change the comparison.** The current implementation already sends Gemini 3.8 `low` reasoning and excludes reasoning text from its response. That is appropriate: Google explicitly says `minimal` is unsupported for 3.8 and returns an error. Switching that setting to `minimal` is not a valid optimization. [Gemini 3.8 documentation](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash).

| Candidate | Initial benchmark configuration | Important detail |
| --- | --- | --- |
| Gemini 3.8 Flash | `reasoning: {"effort":"low","exclude":true}` | Keep the existing baseline. |
| Gemma 4 31B | `reasoning: {"enabled":false}` | OpenRouter catalog reports optional reasoning, disabled by default; verify the resolved provider honors the request. |
| GPT-OSS 120B | `reasoning: {"effort":"low","exclude":true}` | Catalog marks reasoning mandatory; do not assume it can be eliminated. |
| Gemini 3.5 Flash-Lite | `reasoning: {"effort":"minimal","exclude":true}` | Supports minimal, unlike 3.8. |
| GPT-5.6 Luna | `reasoning: {"effort":"none","exclude":true}` | OpenAI documents medium as the default; changing only the model name would leave that source of latency uncontrolled. |

These are documented starting configurations, not requests tested in this research. `exclude: true` hides reasoning from the response; it does not disable the computation or its token cost. The repository only sets reasoning options automatically for Gemini families. Sources: [OpenRouter reasoning guide](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens), [live model metadata](https://openrouter.ai/api/v1/models), [GPT-5.6 Luna documentation](https://developers.openai.com/api/docs/models/gpt-5.6-luna), [Google Flash-Lite guidance](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/gemini/3-5-flash-lite).

The app also sends `temperature: 0` and `top_p: 1` universally. They are not uniformly supported across candidate endpoints. The OpenRouter Luna endpoint, for example, does not advertise these sampling controls. For an intentional comparison, build valid requests per endpoint and record the parameters actually supported. First test the existing prompt, then evaluate any prompt or sampling changes separately; otherwise model and prompt effects become confounded. [OpenRouter Luna endpoint metadata](https://openrouter.ai/api/v1/models/openai/gpt-5.6-luna/endpoints).

**Other options considered.** Qwen 3.8 27B is particularly interesting if we later integrate Cerebras directly. Cerebras lists approximately 1,500 tok/s, $0.99/$1.49 per million tokens, a 128K paid context, and `reasoning_effort: "none"` to disable thinking. However, the OpenRouter Qwen endpoint snapshot contains no Cerebras provider. Putting `qwen/qwen3.8-27b` into Settings therefore does not obtain that advertised Cerebras speed. It would require a separate direct integration or a newly available OpenRouter route. [Cerebras Qwen documentation](https://inference-docs.cerebras.ai/models/qwen-3.8-27b.md), [OpenRouter Qwen endpoints](https://openrouter.ai/api/v1/models/qwen/qwen3.8-27b/endpoints).

GPT-OSS on Groq is also worth considering as a hosting alternative: the snapshot showed approximately 304 tok/s at $0.15/$0.60 per million tokens. This could be useful if the Cerebras route has availability problems. Provider failover needs its own timing measurements. [OpenRouter GPT-OSS providers](https://openrouter.ai/openai/gpt-oss-120b).

Claude Haiku 4.5 is a reasonable additional editorial quality comparison if the first candidates over-edit. Its direct Anthropic route was $1/$5 per million, with 47 tok/s and 0.74 s displayed latency in our snapshot. That gives it no obvious speed advantage to justify including it in the first speed-focused trial. This is a prioritization decision, not a claim about inferior accuracy. [OpenRouter Haiku providers](https://openrouter.ai/anthropic/claude-haiku-4.5).

Gemini 3.1 Flash-Lite ($0.25/$1.50) and 2.5 Flash-Lite ($0.10/$0.40) remain cheaper candidates in the current catalog. I would start with 3.5 Flash-Lite, then test these if cost or measured latency still warrants it. Larger flagship models could serve as evaluation aids, but this research provides no reason to pay their latency cost on every ordinary cleanup. [OpenRouter model catalog](https://openrouter.ai/api/v1/models).

**Cost is unlikely to be the deciding factor for personal use.** Assuming 1,000 input tokens including instructions and 300 visible output tokens per cleanup, the following costs are calculated from the provider prices above:

| Endpoint | Cost for 1,000 cleanup requests |
| --- | ---: |
| Gemini 3.8 Flash / AI Studio Priority, current discount | $3.38 |
| Gemma 4 31B / Cerebras | $1.44 |
| GPT-OSS 120B / Cerebras | $0.58 |
| Gemini 3.5 Flash-Lite / AI Studio | $1.05 |
| GPT-5.6 Luna / OpenAI | $0.56 |

These estimates exclude additional reasoning tokens, transcription, retries, cache adjustments, taxes, and credit-purchase fees. They are not an estimate of total app cost. At these volumes, preserving meaning and saving a second matter more than saving a fraction of a cent per request.

**How I would decide whether to switch.** Run a controlled cleanup-only comparison against the same frozen draft transcripts and the exact current editing instructions. A sensible first pass is 100 representative transcripts, all five candidates, and three repetitions per case. Include short, medium, and long dictation; test French, English, and mixed language if these are part of actual usage. Use synthetic cases for an initial smoke check, but require representative human dictation before selecting a default.

The evaluation should include these failure modes:

| Example or category | Required behavior |
| --- | --- |
| “Ship Tuesday, sorry, Thursday.” | Keep Thursday; remove the explicitly replaced day. |
| “We could use Redis. Another option is Postgres.” | Preserve both alternatives. |
| “This is very, very important. Maybe we should wait.” | Preserve emphasis and uncertainty. |
| “Do not deploy version 3.8.” | Preserve negation and the exact version. |
| Unfamiliar model names, people, acronyms, paths, identifiers | Do not substitute more familiar spellings or values. |
| Dates, decimal numbers, currencies, quantities | Do not change values except for explicit corrections. |
| “I like this” versus filler uses of “like” | Distinguish meaning from disfluency. |
| A dictated question or instruction | Edit it; do not answer or execute it. |
| French/English switching | Preserve language and technical vocabulary. |
| An already clean passage or an unfinished thought | Leave it unchanged when no edit is warranted. |
| Long passages with several topics | Preserve all distinct details and their order. |

Grade fidelity first: changed facts, numbers, names, negations, omitted ideas, unnecessary rewriting, and answering the transcript. Score disfluency removal and punctuation separately. Word error rate alone is unsuitable for cleanup because correct filler removal deliberately differs from the raw transcript. Use blinded human comparisons on critical cases; an LLM judge can assist but should not be the sole authority. The unchanged raw transcript is a useful fidelity control, but cannot win the overall evaluation simply by doing no cleanup.

For each request record the requested and resolved model/provider, reasoning configuration, input/output/reasoning token counts, complete output, errors, unexpected reasoning text in the answer, truncation/finish reason, cost, and full cleanup latency. Track p50 and p95 by transcript length, plus worst failures. Randomize model order, sample more than one time period, and include both cold and warm requests. Use the real application's non-streaming request path for its timing result; separate streamed diagnostic runs can measure first-answer latency. Then validate the top candidate's actual Stop-to-paste time in the app.

My proposed release gate is no observed additional critical meaning errors on a held-out set, acceptable cleanup quality, and a meaningful p95 Stop-to-paste improvement—roughly a second on the dictations where waiting is noticeable. This is a suggested product criterion, not an established benchmark. A small clean sample does not prove a zero error rate; expand the corpus when differences are close.

**Repository implications for a future trial.** The existing Swift benchmark can run its `whisper-gemini-text` strategy against several model IDs and share a Whisper draft within a run. However, it starts from audio and uses Whisper, not the app's current live draft. Its reported completion tok/s divides tokens by the entire request duration, so it is not directly comparable to provider decode throughput. The Python benchmark is also oriented around audio strategies. Sources: [BenchmarkCommand.swift](app/Sources/SuperSamuelApp/BenchmarkCommand.swift), [DictationEngine.swift](app/Sources/SuperSamuelApp/DictationEngine.swift), [recording_benchmark.py](benchmark/recording_benchmark.py).

For this decision, add a small cleanup-only benchmark that consumes frozen draft text and reproduces the service request, with explicit provider and reasoning controls. This avoids retranscribing or re-uploading audio for every editing comparison. During measurement, pin `cerebras/fp16` with provider fallbacks disabled so a slower alternative cannot silently contaminate the Cerebras results; count failures honestly. Production can use explicitly tested fallbacks. OpenRouter's `allow_fallbacks` changes providers for a model; it is not by itself a Gemini model fallback. [Provider routing](https://openrouter.ai/docs/guides/routing/provider-selection).

The app currently prefers `google-ai-studio/priority` specifically for Gemini 3.8 and otherwise sorts by throughput. A model-name edit alone does not ensure the intended provider or reasoning configuration. Changing all requests to latency sorting is not automatically better either: short responses favor startup time, longer responses can favor throughput. OpenRouter supports both sorts; select the policy from our measured completion times. [Provider routing](https://openrouter.ai/docs/guides/routing/provider-selection).

I would keep the architecture to one cleanup call per dictation. Automatically asking a second model to review every result would restore much of the delay we are trying to remove. API failure fallback also cannot detect a successful response that silently changes a number. The saved original draft remains valuable, but the primary protection should be choosing a model that passes the editing evaluation.

**Decision.** Gemma 4 31B on Cerebras is my first challenger to Gemini for text cleanup, with GPT-OSS 120B on Cerebras alongside it. Keep Gemini 3.8 as the baseline until one proves equally faithful on representative transcripts. Keep live transcription and saved-audio recovery as they are while making this comparison. The likely opportunity is a smaller, faster editor after the existing recognizer; the remaining uncertainty is task-specific fidelity, not whether roughly 500 tok/s hosting exists.
