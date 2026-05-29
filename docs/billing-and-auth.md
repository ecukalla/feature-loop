# Billing & auth

feature-loop's engine runs **every phase as `claude -p`** — Claude Code's headless /
"print" mode: build, test, security audit, simplify, and the retrospective
(`bin/feature-loop:186,271,277,278,370`). How those runs are billed depends on the auth
mode you pick when you launch `feature-loop-docker`.

## The two auth modes

| Mode | How you select it | Billed as |
|------|-------------------|-----------|
| API key | `ANTHROPIC_API_KEY=… feature-loop-docker …` | Anthropic API usage, at API rates |
| Subscription (OAuth) | `feature-loop-docker --auth oauth …` | See the 2026-06-15 change below |

Running `/auto-feature` yourself *inside* a Claude Code TUI session is a different path —
see [What is *not* affected](#what-is-not-affected).

## Heads-up: the 2026-06-15 Agent SDK billing change

Starting **15 June 2026**, Anthropic moves *programmatic* Claude usage — the **Claude
Agent SDK**, **`claude -p`**, and **Claude Code GitHub Actions** — **off your Pro/Max
subscription's usage limits** and onto a **separate monthly credit**, metered at **full
API rates**:

| Plan | Monthly programmatic credit |
|------|------|
| Pro | $20 |
| Max 5× | $100 |
| Max 20× | $200 |
| Team Standard | $20 / seat |
| Team Premium | $100 / seat |

- The credit **does not roll over** — it resets at the start of each billing cycle.
- You **claim it once** through your Claude account; after that it refreshes
  automatically. Team / Enterprise admins receive an email to claim before 15 June 2026.
- When the credit runs out, further usage bills at **full API rates** through an opt-in
  **"usage credits"** toggle — or is **rejected** if you leave that toggle off.

### What this means for feature-loop

Because the engine is entirely `claude -p`, **every** feature-loop run is programmatic
usage:

- **`--auth oauth` (subscription).** Before 15 June 2026 these runs drew from your plan's
  normal usage limits. **After 15 June 2026 they draw from the separate monthly Agent SDK
  credit above, then bill at full API rates** once it is exhausted. feature-loop loops
  build → gates → fix (several `claude -p` calls per iteration, up to `FL_MAX_ITERS`), so
  a handful of large runs can consume a month's credit. `feature-loop-docker` prints a
  one-line reminder to stderr on each `--auth oauth` run; set `FL_NO_BILLING_NOTICE=1` to
  silence it.
- **`ANTHROPIC_API_KEY` (API key).** Unchanged — these runs were always billed at API
  rates and never drew from a subscription.

### What is *not* affected

Interactive Claude Code — the terminal / IDE TUI, including running `/auto-feature`
yourself inside a Claude Code session — **keeps using your subscription usage limits** as
before. Only headless `claude -p` / Agent SDK usage moves to the separate credit.

## What to do

1. **Claim your programmatic credit** once it appears in your Claude account (watch for
   Anthropic's notice before 15 June 2026).
2. **Decide on the "usage credits" toggle.** On → overflow bills at API rates and runs
   keep working; off → runs fail once the monthly credit is spent.
3. **Want predictable, decoupled billing?** Run feature-loop with an explicit
   `ANTHROPIC_API_KEY` instead of `--auth oauth`. That path is unchanged and keeps your
   loop spend separate from your subscription.
4. **Watch your spend.** Lower `FL_MAX_ITERS` and keep `$FL_GATES` fast to reduce the
   number of `claude -p` iterations per run.

## Source

- [Anthropic Help Center — Use the Claude Agent SDK with your Claude plan](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan)
