# Snowflake KV Cache and Prefix Caching

**Audience:** FinOps practitioners, data engineers, platform teams, and non-AI engineers  
**Purpose:** Explain KV Cache, Prefix Caching, Prefill, and Decode in plain language, with FinOps implications for Snowflake AI  
**Related training:** Module 07 (KV Cache Optimization)

---

## One-sentence summary

An LLM builds a memory of the prompt so it does not re-think the same tokens again. **KV Cache** keeps that memory during a chat. **Prefix Caching** shares the stable front of the prompt across many requests and users.

---

## Plain-language glossary

| Term | Simple meaning |
|------|----------------|
| **Token** | A small chunk of text the model reads or writes (roughly a word or part of a word). |
| **KV (Keys and Values)** | Internal math the model builds for each token so it can remember context. Think of it as sticky notes the model attaches to every piece of text it has already read. |
| **KV Cache** | Storage of those sticky notes so the model does not rebuild them from scratch. |
| **Prefill** | The "reading" phase: process the prompt and build the KV Cache. This drives Time-to-First-Token. |
| **Decode** | The "writing" phase: generate the answer one token at a time, adding each new token to the cache. |
| **Prefix** | The stable front of the prompt (system instructions, docs, tools) that should stay identical across requests. |
| **Suffix** | The changing end of the prompt (date, user id, user question). |
| **Prefix Caching** | Reusing the KV Cache for a shared, identical prefix across different requests or users. |
| **Cache hit** | The system recognizes the prefix and reuses stored KV. Faster and cheaper. |
| **Cache miss** | The prefix looks new (even by one character), so the system rebuilds KV from scratch. |

On Snowflake AI bills you often see:

| Billing label | What it means |
|---------------|---------------|
| `input` | New prompt text that was not served from cache |
| `output` | Tokens the model generated |
| `cache_write_input` | First-time cost to store a reusable prefix in cache |
| `cache_read_input` | Cheaper reuse of that stored prefix |

---

## 1. What the KV Cache normally does

When an LLM processes a prompt, it calculates **Keys** and **Values** for every token so it can understand context.

- **Without a cache:** the model recalculates Keys and Values for every token, every request.
- **With a regular KV Cache:** during one conversation, the model keeps those values so it does not re-read the whole chat history on the next turn.

### Prefill vs Decode (one turn)

```text
Turn 1
  Prefill  -> read the prompt, build KV Cache
  Decode   -> write the answer, append answer tokens to KV Cache
```

### Inside a single chat session (standard KV Cache)

1. **Turn 1 input:** user asks a question -> Prefill builds the cache.  
2. **Turn 1 output:** model answers -> Decode appends answer tokens to the KV Cache.  
3. **Turn 2 input:** user asks a follow-up -> the model already has the original question and the prior answer in cache.

**Takeaway:** In one session, the KV Cache grows as both user messages and model answers are fed back into memory so the conversation continues without full re-reads.

---

## 2. Where Prefix Caching comes in

Frameworks such as vLLM and Snowflake-oriented serving stacks (including approaches like SwiftKV) go further: they can **share** KV Cache for a common prefix across different users and requests.

Example:

- 1,000 users ask different questions.
- All of them start with the same 4,000-token system prompt or documentation block.
- The system computes KV for that 4,000-token block **once**, stores it, and reuses it.

### Across brand-new requests (Prefix Caching)

If User A ends a session and User B asks a new question:

- User A's **answers** are not shared with User B.
- What can be shared is the **static Cached Prefix Block** (system instructions, shared docs, stable tool schemas).

**Takeaway:**

- **KV Cache (session):** grows dynamically during a chat, including model outputs.  
- **Prefix Caching:** freezes and reuses stable **inputs** (the shared front of the prompt) across users.

---

## 3. Why "stabilizing" the prefix matters

The system identifies cache chunks with a **cryptographic hash** (a digital fingerprint) of the prompt tokens.

- Change one character, space, timestamp, or early variable and the hash changes.
- A hash change causes a **cache miss**.
- On a miss, the system treats the prefix as new and recomputes KV from scratch.

So FinOps and latency both depend on keeping the large shared front of the prompt **byte-identical**.

---

## 4. Prompt layout: bad vs optimized

### The bad way (destroys the cache)

Dynamic data sits at the top. Every request looks unique. Cache hit rate goes toward **0%**.

```text
--- START OF PROMPT ---
[Current Date]: 2026-09-17
[User Query]: "Show me the top customers"
[System Instructions]: You are a sales analyst. Answer from the 2026 revenue tables. Be concise.
--- END OF PROMPT ---
```

Because date and user query appear early, the left-to-right fingerprint changes every time. The engine re-evaluates almost everything.

### The optimized way (stable prefix)

Keep system instructions and docs first. Push volatile fields to the end.

```text
--- START OF PROMPT (Cached Prefix Block) ---
[System Instructions]: You are a sales analyst. Answer from the 2026 revenue tables. Be concise.
--- START OF SUFFIX (Dynamic / Changing Variables) ---
[Current Date]: 2026-09-17
[User Query]: "Show me the top customers"
--- END OF PROMPT ---
```

The large instruction block stays identical. Later requests can hit the cache and only process the new suffix tokens.

---

## 5. Optimizing LLM performance via Prefix Caching

### The problem

- LLMs evaluate prompts from left to right.
- If a dynamic variable (date, user query, session id) sits at the top, the prompt fingerprint changes immediately.
- The engine recalculates from scratch. Prefill slows down. Cost rises.

### The solution

- Push volatile values to the **suffix** (absolute end).
- Keep the **prefix** stable and byte-identical across requests.
- Result: higher cache hit rate, better Time-to-First-Token (TTFT), lower repeated input spend.

### Presentation takeaway

| Mechanism | What it remembers | Scope |
|-----------|-------------------|--------|
| **KV Cache** | Conversation state, including model outputs | One chat session |
| **Prefix Caching** | Stable system/docs prefix only | Many requests and users |

- KV Cache grows during a chat by feeding outputs back into memory.  
- Prefix Caching freezes shared inputs so many users reuse the same front of the prompt.

---

## 6. KV Cache vs Prefix Cache (side by side)

| | **Standard KV Cache** | **Prefix Caching** |
|--|------------------------|--------------------|
| **Main job** | Remember this conversation | Reuse a shared prompt front |
| **What is stored** | Prompt + prior turns + model answers | Stable system/docs prefix |
| **Shared across users?** | No | Yes, for identical prefixes |
| **Broken by** | New session / expired context | Any early change in the prefix |
| **FinOps signal** | Rising `cache_read_input` within a long thread | High hit rate on shared system prompts |

---

## 7. Input optimization vs output optimization

These are related FinOps levers, but they are not the same.

| Feature | Input token optimization (Prefix Caching / KV Cache) | Output token optimization (response minimization) |
|---------|------------------------------------------------------|-----------------------------------------------------|
| **Primary target** | Input tokens (the prompt you send) | Output tokens (the response you get) |
| **Cost savings mechanism** | Reuse compute/memory so the model skips re-reading large system blocks | Restrict length so the model generates fewer billable tokens |
| **Core technique** | Move variables to the end to stabilize the hash | Instruct "be brief", "output JSON only", use schemas |
| **Primary metric improved** | Time-to-First-Token (TTFT) / Prefill speed | Generation time / per-token output cost |

Use both:

1. Stabilize and cache the prefix (input).  
2. Keep answers as short as quality allows (output).

---

## 8. FinOps checklist for Snowflake AI

1. Put **system instructions, policies, and docs first**.  
2. Put **date, user, filters, and the live question last**.  
3. Avoid rebuilding the full prompt string on every turn when history can stay stable.  
4. Prefer one long session with reused context over restarting the same large prefix repeatedly.  
5. Track weekly:
   - `cache_read_input` vs fresh `input`
   - cache hit rate / `cache_read_pct_of_prompt`
   - TTFT for agent and CoCo workloads  
6. Remember: a high hit rate helps, but volume can still grow. Pair cache KPIs with budgets and use-case attribution.

---

## 9. Quick mental model

```text
Stable front of prompt  = Prefix  = cache candidate
Changing end of prompt  = Suffix  = always new work

Prefill  = read and build memory
Decode   = write and extend memory

Session KV Cache     = "remember this chat"
Prefix Caching       = "reuse this shared intro for everyone"
```

---

## 10. Where to go next in this repo

- Training Module 07: `training/modules/07-kv-cache-optimization.html`
- SQL for cache KPIs: `training/sql/07-kv-cache.sql`
- Pricing references: [Snowflake AI pricing](https://docs.snowflake.com/en/user-guide/snowflake-cortex/pricing) and the [Credit Consumption Table](https://www.snowflake.com/legal-files/CreditConsumptionTable.pdf)

---

## Disclaimer

This guide is for education and FinOps practice. Exact cache behavior, TTL, and credit rates depend on Snowflake product surface (AISQL, CoCo, CoWork, Agents, REST) and current published pricing. Validate against your account and contract.
