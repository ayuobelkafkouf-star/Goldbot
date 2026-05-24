# CLAUDE.md

Guidance for AI assistants working in this repository.

## What this repo is

A single trading strategy for **XAUUSD (gold)** maintained in two parallel implementations:

- `GoldBot_XAUUSD.pine` — TradingView Pine Script v5 `strategy()` (treated as the **source of truth**; new logic lands here first).
- `GoldBot_XAUUSD.mq5` — MetaTrader 5 Expert Advisor, a hand-port of the Pine logic to MQL5.

There is no build system, no tests, no package manager. Both files are deployed by pasting/compiling into their respective platforms (TradingView and MetaEditor). Comments and UI labels are in **Italian** — keep new strings in Italian to match.

## Strategy at a glance (v5.2)

- **Symbol / timeframes:** XAUUSD on M15, with H1 used for higher-timeframe trend and structure targets.
- **Entry stack:** H1 trend ∧ M15 trend ∧ price retesting a tracked supply/demand zone ∧ spike + body-confirmation candle ∧ RSI gate ∧ score ≥ threshold ∧ all filters pass ∧ no open position.
- **Three operating modes** (`mode` / `InpMode`):
  - **Conservativo** — London/NY overlap only (Rome 13–17), score floor 60, max 5 trades/day, default cooldown.
  - **Sessione Estesa** — Rome 8–20, score floor forced to ≥70 (quality protected), max 5 trades/day.
  - **Aggressivo** — Rome 8–20, score floor 60, max 10 trades/day, cooldown 2 bars, looser zone tolerance (0.7 ATR).
- **Multi-zone S/D:** up to `max_zones` supply + `max_zones` demand boxes seeded by M15 pivots (`pivot_left=5`, `pivot_right=3`), invalidated on close beyond zone + 0.5·ATR.
- **Scoring (0–100):** H1 trend 25 · M15 trend 20 · zone retest 20 · RSI window 15 · volume>1.2×SMA20 10 · ATR ok 10.
- **Risk:** `risk_pct` of equity per trade; SL = pivot-buffered by `sl_atr_mult·ATR`; TP1 = M15 20-bar struct, TP2 = H1 20-bar struct; `tp1_pct` partial at TP1, then break-even, then ATR trailing (`trail_mult`).
- **Protections:** ATR floor, news blackout windows (±30 min around up to 3 events), daily P&L caps (`max_loss`, `max_profit`), bar cooldown after close, drawdown circuit breaker (`dd_threshold` % from equity peak → pause `pause_days`).
- **Timezone:** all session/news math is in **Europe/Rome**. Pine uses `hour(time, "Europe/Rome")`; MQL5 approximates Rome offset in `ComputeTzOffset()` (DST guessed by month — see Gotchas).

## Keeping `.pine` and `.mq5` in sync

When changing strategy logic, change **both files** in the same commit. The Pine version is canonical; the MQL5 should mirror it bar-for-bar. Cross-reference points:

| Concept | Pine (`.pine`) | MQL5 (`.mq5`) |
|---|---|---|
| Mode resolution | `eff_*` block (lines ~99–108) | `ApplyMode()` |
| Pivot zones | `m15_ph` / `m15_pl` push blocks | `DetectPivotHigh/Low`, `PushSupplyZone/PushDemandZone` |
| Zone invalidation | `i_s` / `i_d` while-loops | `InvalidateZones()` |
| Retest detect | `price_at_supply`, `price_at_demand` | `IsAtSupply()`, `IsAtDemand()` |
| Spike + body | `confirm_buy`/`confirm_sell` | same locals inside `ProcessNewBar()` |
| Filters | `hour_ok`, `atr_ok`, `news_ok`, `cooldown_ok`, `trades_ok`, `day_ok`, `circuit_ok` | same names inside `ProcessNewBar()` |
| Score | `score_sell`/`score_buy` block | mirror block in `ProcessNewBar()` |
| Entry | `strategy.entry` + `strategy.exit` | `OpenLong()` / `OpenShort()` |
| TP1 / BE / trail | partial-close + `strategy.exit` blocks | `ManageOpenPositions()` |

Defaults must match across the two files. If a parameter's default changes in Pine, update the `Inp*` default in MQL5.

## Repaint discipline (Pine)

Live signals must use **closed-bar** data. The helper

```
f_sec(_tf, _src) => request.security(syminfo.tickerid, _tf, _src[1], lookahead=barmerge.lookahead_off)
```

is the only sanctioned way to pull HTF series. Never call `request.security` with `lookahead_on` or without the `[1]` shift. The MQL5 equivalent is reading indicator buffers at `shift=1` via `GetBuf(handle, 1, out)` inside `ProcessNewBar()` (which itself only runs on a new M15 bar).

## Workflow

- **Branch:** develop on `claude/claude-md-docs-dTBu6` (or whatever branch the current task specifies). Do **not** push elsewhere without explicit permission.
- **Commits:** concise, scope-prefixed style matches existing history (e.g. `Multi-zone tracking, aggressive mode, score filter (v5.2)`, `Add MT5 Expert Advisor conversion (v5.2 MQL5)`). Bump the `v5.x` tag in the commit subject when shipping a logic change, and update the `strategy(...)` shortTitle in `.pine` plus `#property version` in `.mq5` accordingly.
- **No tests.** Verification means: Pine compiles in TradingView (look at the `// @version=5` syntax constraints); MQL5 compiles in MetaEditor without warnings. There's nothing to run locally — don't fabricate a test command.
- **Don't add tooling files** (package.json, CI configs, etc.) unless the user asks.

## Pine v5 gotchas in this file

- **Forward references:** `eff_zone_tol` is declared before the multi-zone loops that consume it — a previous fix (`f52c4cc`). Keep effective-value declarations above their first use.
- **Array safety:** zone arrays (`sup_tops`, `sup_bots`, `sup_boxes`, and demand counterparts) must stay length-aligned. Any push/shift/remove touches all three for that side.
- **Boxes:** zone boxes are visual only; logic relies on the float arrays. When invalidating, `box.delete` first, then `array.remove` from the float arrays — order matters in Pine to avoid leaks.
- **`strategy.exit` re-issue:** trailing/BE updates re-call `strategy.exit("BUY_EXIT", from_entry="BUY", stop=..., limit=...)` to overwrite the bracket. The `from_entry` ID must match the original `strategy.entry` ID exactly.

## MQL5 gotchas

- **Tester limitation:** the EA holds **one position per magic** (`HasOpenPosition`/`GetOpenPosition` filter by `_Symbol` + `InpMagic`). Don't add logic that opens parallel positions without rethinking that.
- **DST approximation:** `ComputeTzOffset()` treats April–October as CEST. This is a known approximation — real DST transitions in late March / late October will be off by an hour for a few days. Acceptable for a session filter; do **not** rely on it for precise news minute-windows.
- **Partial close + BE:** after `Trade.PositionClosePartial`, `Trade.PositionModify(_Symbol, g_trail_sl, g_tp2_px)` shifts SL to entry. Trailing then only ratchets in the favorable direction. Don't introduce reverse SL moves.
- **Lot sizing:** `CalculateLotSize` floors to `SYMBOL_VOLUME_STEP` and clamps to `[MIN, MAX]`. If risk_cash is tiny it will floor to `MIN` — that's intentional, not a bug.
- **`OnTick` cadence:** signal evaluation is gated by a new M15 bar (`g_last_m15_bar` check). Position management runs every tick. Keep this split.

## Conventions

- **Language:** Italian for user-facing labels, group names, tooltips, dashboard text, and `alertcondition` messages. English is fine inside code-only comments if it's clearer.
- **Naming:** Pine uses `snake_case`; MQL5 uses `InpPascalCase` for inputs, `g_snake_case` for globals, `PascalCase` for functions. Don't mix.
- **Numbers:** percentages are written as `0.5` meaning 0.5% (not 0.005), consistent with how `risk_pct` / `InpRiskPct` is consumed.
- **No emojis in code unless they're already part of the dashboard strings** (which use ✅ ❌ 🟢 🔴 🟡 ⚡ 🕐 🛑 — match those if extending the dashboard).

## Out of scope

- Don't introduce a build system, package manager, CI, or auxiliary scripts unless the user asks.
- Don't create README.md or other docs unless asked — this CLAUDE.md is the working reference.
- Don't refactor the Pine or MQL5 file structure (section banners with `// ───` separators) just for tidiness; preserve the existing layout so the two files stay easy to diff against each other.
