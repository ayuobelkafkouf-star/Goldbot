"""AGENTE 2 - GUARDIANO (Filtri & Permessi).

Decide SE e' il momento giusto per operare. Pura logica via-libera/stop su
orari, sessione, notizie, cooldown, limiti giornalieri e circuit breaker.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Optional

from ..core.config import Config
from ..core.models import Permission


@dataclass
class AccountState:
    """Stato di protezione del conto, condiviso con l'orchestratore."""
    trades_today: int = 0
    day_counter: int = 0
    last_day: int = -1
    pause_until_day: int = 0
    last_close_time: Optional[datetime] = None
    eq_peak: float = 0.0
    day_eq: float = 0.0


class GuardianAgent:
    def __init__(self, config: Config):
        self.cfg = config

    def _hour_ok(self, hour: int) -> bool:
        cfg = self.cfg
        if cfg.eff_use_session:
            return cfg.session_start <= hour < cfg.session_end
        if cfg.eff_force_hours:
            return cfg.start_hour <= hour < cfg.end_hour
        return True

    def _is_news_time(self, hour: int, minute: int) -> bool:
        if not self.cfg.use_news:
            return False
        cur = hour * 60 + minute
        for nh, nm in self.cfg.news_times:
            n = nh * 60 + nm
            if n - self.cfg.news_before <= cur <= n + self.cfg.news_after:
                return True
        return False

    def check(self, now: datetime, equity: float, atr_local: float, st: AccountState) -> Permission:
        cfg = self.cfg
        hour, minute = now.hour, now.minute

        if not self._hour_ok(hour):
            return Permission(False, "fuori orario operativo")

        if cfg.use_atr and atr_local < cfg.atr_min:
            return Permission(False, f"ATR troppo basso ({atr_local:.2f} < {cfg.atr_min})")

        if self._is_news_time(hour, minute):
            return Permission(False, "finestra notizie")

        # cooldown
        if st.last_close_time is not None:
            elapsed = (now - st.last_close_time).total_seconds()
            if elapsed < cfg.eff_cooldown * 15 * 60:
                return Permission(False, "cooldown attivo")

        # max trade/giorno
        if st.trades_today >= cfg.eff_max_trades:
            return Permission(False, "max trade giornalieri raggiunto")

        # limiti P&L giornaliero
        day_pct = (equity - st.day_eq) / st.day_eq * 100.0 if st.day_eq > 0 else 0.0
        if day_pct <= -cfg.max_loss:
            return Permission(False, f"perdita giornaliera max ({day_pct:.2f}%)")
        if day_pct >= cfg.max_profit:
            return Permission(False, f"profitto giornaliero max ({day_pct:.2f}%)")

        # circuit breaker drawdown
        if equity > st.eq_peak:
            st.eq_peak = equity
        dd_pct = (st.eq_peak - equity) / st.eq_peak * 100.0 if st.eq_peak > 0 else 0.0
        if cfg.use_circuit and dd_pct >= cfg.dd_threshold and st.day_counter >= st.pause_until_day:
            st.pause_until_day = st.day_counter + cfg.pause_days
        if cfg.use_circuit and st.day_counter < st.pause_until_day:
            return Permission(False, "circuit breaker: pausa drawdown")

        return Permission(True, "ok")
