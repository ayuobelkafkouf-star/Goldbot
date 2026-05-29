"""AGENTE 4 - ESECUTORE (Trade Manager).

Decide COME eseguire e gestire la posizione: apertura ordine, chiusura
parziale a TP1, break-even e trailing stop su ATR. Parla solo con il Broker.
"""
from __future__ import annotations

import math

from ..broker.base import Broker
from ..core.config import Config
from ..core.models import Direction, Position, RiskPlan, Signal


class ExecutorAgent:
    def __init__(self, config: Config, broker: Broker, lot_step: float = 0.01):
        self.cfg = config
        self.broker = broker
        self.lot_step = lot_step

    def open_trade(self, signal: Signal, plan: RiskPlan) -> bool:
        """Apre la posizione con SL e TP2 dal piano di rischio."""
        if not plan.valid:
            return False
        pos = self.broker.open(signal.direction, plan.lots, sl=plan.sl, tp=plan.tp2)
        if pos is None:
            return False
        pos.tp1_price = plan.tp1
        pos.tp2_price = plan.tp2
        return True

    def manage(self, current_price: float, atr_local: float) -> None:
        """Da chiamare ad ogni barra: TP1 parziale, break-even, trailing."""
        cfg = self.cfg
        pos = self.broker.position()
        if pos is None:
            return

        is_long = pos.direction == Direction.BUY

        # --- TP1: chiusura parziale + break-even ---
        if not pos.tp1_hit and pos.tp1_price > 0:
            hit = current_price >= pos.tp1_price if is_long else current_price <= pos.tp1_price
            if hit:
                close_vol = pos.volume * cfg.tp1_pct / 100.0
                close_vol = math.floor(close_vol / self.lot_step) * self.lot_step
                if 0 < close_vol < pos.volume:
                    self.broker.close_partial(close_vol, reason="TP1")
                    pos = self.broker.position()
                    if pos is not None:
                        pos.tp1_hit = True
                        if cfg.use_be:
                            pos.be_active = True
                            pos.trail_sl = pos.entry_price
                            self.broker.modify(sl=pos.trail_sl, tp=pos.tp2_price)

        # --- Trailing stop su ATR (dopo TP1/BE) ---
        if cfg.use_trail and pos is not None and pos.be_active:
            if is_long:
                new_sl = current_price - atr_local * cfg.trail_mult
                if new_sl > pos.trail_sl and new_sl > pos.entry_price:
                    pos.trail_sl = new_sl
                    self.broker.modify(sl=new_sl, tp=pos.tp2_price)
            else:
                new_sl = current_price + atr_local * cfg.trail_mult
                if (pos.trail_sl == 0 or new_sl < pos.trail_sl) and new_sl < pos.entry_price:
                    pos.trail_sl = new_sl
                    self.broker.modify(sl=new_sl, tp=pos.tp2_price)
