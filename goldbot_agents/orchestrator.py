"""ORCHESTRATORE.

Coordina i 4 agenti in catena su ogni barra M15:
    ANALISI -> GUARDIANO -> RISK -> ESECUTORE
Mantiene lo stato del conto (giorni, trade, picco equity) e gestisce il
broker simulato barra per barra.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import List

import pandas as pd

from .agents.analysis import AnalysisAgent, MarketSnapshot
from .agents.executor import ExecutorAgent
from .agents.guardian import AccountState, GuardianAgent
from .agents.risk import RiskAgent, RiskContext
from .broker.paper_broker import PaperBroker
from .core.config import Config
from .core.models import Bar, Direction


@dataclass
class RunReport:
    initial_balance: float
    final_balance: float
    final_equity: float
    n_trades: int
    wins: int
    losses: int
    equity_curve: List[float] = field(default_factory=list)

    @property
    def win_rate(self) -> float:
        return self.wins / self.n_trades * 100.0 if self.n_trades else 0.0

    @property
    def net_profit(self) -> float:
        return self.final_balance - self.initial_balance

    @property
    def return_pct(self) -> float:
        return self.net_profit / self.initial_balance * 100.0


class Orchestrator:
    def __init__(self, config: Config):
        self.cfg = config
        self.broker = PaperBroker(config)
        self.analysis = AnalysisAgent(config)
        self.guardian = GuardianAgent(config)
        self.risk = RiskAgent(config)
        self.executor = ExecutorAgent(config, self.broker)
        self.account = AccountState(
            eq_peak=config.initial_balance,
            day_eq=config.initial_balance,
        )

    def _snapshot(self, df: pd.DataFrame, i: int) -> MarketSnapshot:
        row = df.iloc[i]
        prev = df.iloc[i - 1]
        need = self.cfg.pivot_left + self.cfg.pivot_right + 1
        lo = max(0, i - need + 1)
        highs = df["high"].values[lo:i + 1].tolist()
        lows = df["low"].values[lo:i + 1].tolist()
        return MarketSnapshot(
            time=df.index[i].to_pydatetime(),
            m15_open=row["open"], m15_high=row["high"],
            m15_low=row["low"], m15_close=row["close"],
            m15_high_prev=prev["high"], m15_low_prev=prev["low"],
            h1_ema_fast=row["h1_ema_fast"], h1_ema_slow=row["h1_ema_slow"],
            m15_ema_fast=row["ema_fast"], m15_ema_slow=row["ema_slow"],
            m15_rsi=row["rsi"], atr_m15=row["atr"], atr_local=row["atr"],
            vol_now=row["volume"], vol_sma=row["vol_sma"] if row["vol_sma"] == row["vol_sma"] else 0.0,
            m15_highs=highs, m15_lows=lows,
        )

    def run(self, df: pd.DataFrame) -> RunReport:
        curve: List[float] = []
        for i in range(1, len(df)):
            row = df.iloc[i]
            bar = Bar(
                time=df.index[i].to_pydatetime(),
                open=row["open"], high=row["high"],
                low=row["low"], close=row["close"], volume=row["volume"],
            )

            # 1) aggiorna broker (SL/TP) e contabilizza chiusure
            result = self.broker.on_bar(bar)
            if result is not None:
                self.account.trades_today += 1
                self.account.last_close_time = bar.time

            # 2) rollover giornaliero
            day = bar.time.timetuple().tm_yday
            if day != self.account.last_day:
                self.account.last_day = day
                self.account.day_counter += 1
                self.account.trades_today = 0
                self.account.day_eq = self.broker.equity

            # 3) gestione posizione aperta (Esecutore: TP1/BE/trail)
            self.executor.manage(bar.close, row["atr"])

            # 4) catena di decisione (sempre aggiorna le zone via ANALISI)
            snap = self._snapshot(df, i)
            signal = self.analysis.update(snap)

            if self.broker.position() is None and signal.has_signal:
                perm = self.guardian.check(bar.time, self.broker.equity, row["atr"], self.account)
                if perm.allowed:
                    ctx = RiskContext(
                        entry_price=bar.close,
                        equity=self.broker.equity,
                        recent_high_m15=row["recent_high_m15"],
                        recent_low_m15=row["recent_low_m15"],
                        recent_high_h1=row["recent_high_h1"],
                        recent_low_h1=row["recent_low_h1"],
                    )
                    plan = self.risk.plan(signal, ctx)
                    if plan.valid:
                        self.executor.open_trade(signal, plan)

            curve.append(self.broker.equity)

        wins = sum(1 for t in self.broker.trades if t.profit > 0)
        losses = sum(1 for t in self.broker.trades if t.profit <= 0)
        return RunReport(
            initial_balance=self.cfg.initial_balance,
            final_balance=self.broker.balance,
            final_equity=self.broker.equity,
            n_trades=len(self.broker.trades),
            wins=wins,
            losses=losses,
            equity_curve=curve,
        )
