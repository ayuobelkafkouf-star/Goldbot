"""Configurazione del sistema, ispirata agli input del GoldBot_XAUUSD.mq5.

Tre modalita' operative (Conservativo / Esteso / Aggressivo) regolano alcuni
parametri effettivi, esattamente come ApplyMode() nell'EA originale.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


class Mode(str, Enum):
    CONSERVATIVE = "conservative"
    EXTENDED = "extended"
    AGGRESSIVE = "aggressive"


@dataclass
class Config:
    # --- Modalita' ---
    mode: Mode = Mode.CONSERVATIVE
    min_score: int = 60
    max_zones: int = 5

    # --- Trend ---
    h1_fast: int = 21
    h1_slow: int = 55
    m15_fast: int = 21
    m15_slow: int = 55

    # --- RSI ---
    rsi_len: int = 14
    rsi_ob: int = 65
    rsi_os: int = 35

    # --- Zone S/D ---
    pivot_left: int = 5
    pivot_right: int = 3
    zone_width: float = 1.5    # larghezza zona in ATR
    zone_tol: float = 0.5      # tolleranza retest in ATR

    # --- Spike + conferma ---
    spike_mult: float = 0.5
    body_mult: float = 0.3

    # --- Rischio ---
    risk_pct: float = 0.5
    sl_atr_mult: float = 0.4
    tp1_pct: int = 70          # % chiusura a TP1
    use_be: bool = True
    use_trail: bool = True
    trail_mult: float = 1.5

    # --- Sessione (ore di Roma) ---
    session_start: int = 13
    session_end: int = 17
    start_hour: int = 8
    end_hour: int = 20

    # --- Protezione (circuit breaker) ---
    use_circuit: bool = True
    dd_threshold: float = 5.0
    pause_days: int = 3

    # --- Filtri ---
    use_atr: bool = True
    atr_min: float = 1.5
    cooldown_bars: int = 5
    max_trades_day: int = 5
    max_loss: float = 1.0      # max perdita % giorno
    max_profit: float = 5.0    # max profitto % giorno

    # --- Notizie (lista di orari Roma da evitare) ---
    use_news: bool = True
    news_times: list = field(default_factory=lambda: [(14, 30)])  # (ora, minuto)
    news_before: int = 30
    news_after: int = 30

    # --- Conto simulato ---
    initial_balance: float = 10_000.0
    # Valore per pip/punto: profitto = (delta_prezzo) * volume * contract_size
    contract_size: float = 100.0   # 1 lotto XAUUSD = 100 once
    spread: float = 0.20           # spread fisso in $ (sim)

    # --------- Valori effettivi derivati dalla modalita' ---------
    @property
    def eff_use_session(self) -> bool:
        return self.mode == Mode.CONSERVATIVE

    @property
    def eff_force_hours(self) -> bool:
        return self.mode in (Mode.EXTENDED, Mode.AGGRESSIVE)

    @property
    def eff_cooldown(self) -> int:
        return 2 if self.mode == Mode.AGGRESSIVE else self.cooldown_bars

    @property
    def eff_max_trades(self) -> int:
        return 10 if self.mode == Mode.AGGRESSIVE else self.max_trades_day

    @property
    def eff_zone_tol(self) -> float:
        return 0.7 if self.mode == Mode.AGGRESSIVE else self.zone_tol

    @property
    def eff_min_score(self) -> int:
        if self.mode == Mode.EXTENDED:
            return max(self.min_score, 70)
        return self.min_score
