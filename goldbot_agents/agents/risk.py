"""AGENTE 3 - RISK MANAGER.

Decide QUANTO rischiare e dove mettere SL/TP. Calcola la size in lotti dal
rischio percentuale e definisce TP1 (struttura M15) e TP2 (struttura H1).
"""
from __future__ import annotations

from dataclasses import dataclass
import math

from ..core.config import Config
from ..core.models import Direction, RiskPlan, Signal


@dataclass
class RiskContext:
    entry_price: float        # prezzo di entrata (close corrente)
    equity: float
    recent_high_m15: float    # massimo struttura M15 (per TP1 long)
    recent_low_m15: float
    recent_high_h1: float     # massimo struttura H1 (per TP2 long)
    recent_low_h1: float


class RiskAgent:
    def __init__(self, config: Config, lot_step: float = 0.01,
                 lot_min: float = 0.01, lot_max: float = 100.0):
        self.cfg = config
        self.lot_step = lot_step
        self.lot_min = lot_min
        self.lot_max = lot_max

    def _lots(self, sl_distance: float, equity: float) -> float:
        if sl_distance <= 0:
            return 0.0
        risk_cash = equity * self.cfg.risk_pct / 100.0
        loss_per_lot = sl_distance * self.cfg.contract_size
        if loss_per_lot <= 0:
            return 0.0
        lots = risk_cash / loss_per_lot
        lots = math.floor(lots / self.lot_step) * self.lot_step
        lots = max(self.lot_min, min(self.lot_max, lots))
        return round(lots, 2)

    def plan(self, signal: Signal, ctx: RiskContext) -> RiskPlan:
        cfg = self.cfg
        if not signal.has_signal:
            return RiskPlan(valid=False, reason="nessun segnale")

        if signal.direction == Direction.BUY:
            sl = signal.entry_ref - signal.atr_local * cfg.sl_atr_mult
            tp1 = ctx.recent_high_m15
            tp2 = max(ctx.recent_high_h1, tp1)  # TP2 (H1) almeno quanto TP1 (M15)
            if not (tp1 > ctx.entry_price and sl < ctx.entry_price):
                return RiskPlan(valid=False, reason="livelli TP/SL non validi (BUY)")
            sl_distance = ctx.entry_price - sl
        else:  # SELL
            sl = signal.entry_ref + signal.atr_local * cfg.sl_atr_mult
            tp1 = ctx.recent_low_m15
            tp2 = min(ctx.recent_low_h1, tp1)   # TP2 (H1) almeno quanto TP1 (M15)
            if not (tp1 < ctx.entry_price and sl > ctx.entry_price):
                return RiskPlan(valid=False, reason="livelli TP/SL non validi (SELL)")
            sl_distance = sl - ctx.entry_price

        lots = self._lots(sl_distance, ctx.equity)
        if lots <= 0:
            return RiskPlan(valid=False, reason="size lotti nulla")

        return RiskPlan(valid=True, lots=lots, sl=sl, tp1=tp1, tp2=tp2, reason="ok")
