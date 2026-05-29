"""Entry point: esegue il sistema multi-agente in paper trading.

Esempi:
    python -m goldbot_agents.main                  # dati sintetici, modalita' conservativa
    python -m goldbot_agents.main --csv dati.csv   # CSV reale
    python -m goldbot_agents.main --mode aggressive --bars 8000
"""
from __future__ import annotations

import argparse

from .core.config import Config, Mode
from .data import feed
from .orchestrator import Orchestrator


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="GoldBot multi-agente (paper trading)")
    p.add_argument("--csv", help="CSV OHLCV M15 (time,open,high,low,close,volume)")
    p.add_argument("--bars", type=int, default=5000, help="barre sintetiche se senza --csv")
    p.add_argument("--seed", type=int, default=42, help="seme dati sintetici")
    p.add_argument("--mode", choices=[m.value for m in Mode], default=Mode.CONSERVATIVE.value)
    p.add_argument("--balance", type=float, default=10_000.0, help="saldo iniziale")
    p.add_argument("--risk", type=float, default=0.5, help="rischio %% per trade")
    return p


def main(argv=None) -> None:
    args = build_parser().parse_args(argv)
    cfg = Config(mode=Mode(args.mode), initial_balance=args.balance, risk_pct=args.risk)

    if args.csv:
        df_m15 = feed.load_csv(args.csv)
        source = args.csv
    else:
        df_m15 = feed.generate_synthetic(bars=args.bars, seed=args.seed)
        source = f"sintetico ({args.bars} barre, seed {args.seed})"

    df = feed.prepare(df_m15, cfg)
    report = Orchestrator(cfg).run(df)

    print("=" * 48)
    print("  GoldBot multi-agente — report paper trading")
    print("=" * 48)
    print(f"  Dati:            {source}")
    print(f"  Modalita':       {cfg.mode.value}")
    print(f"  Barre elaborate: {len(df)}")
    print("-" * 48)
    print(f"  Saldo iniziale:  {report.initial_balance:,.2f}")
    print(f"  Saldo finale:    {report.final_balance:,.2f}")
    print(f"  Equity finale:   {report.final_equity:,.2f}")
    print(f"  Profitto netto:  {report.net_profit:,.2f}  ({report.return_pct:+.2f}%)")
    print("-" * 48)
    print(f"  Trade totali:    {report.n_trades}")
    print(f"  Vinti / Persi:   {report.wins} / {report.losses}")
    print(f"  Win rate:        {report.win_rate:.1f}%")
    print("=" * 48)


if __name__ == "__main__":
    main()
