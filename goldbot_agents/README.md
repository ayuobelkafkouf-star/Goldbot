# GoldBot — Sistema multi-agente (Python)

Versione Python del GoldBot XAU/USD, con la logica di trading divisa in **4 agenti**
specializzati che collaborano in catena. Gira in **paper trading** su dati CSV o
sintetici (nessun denaro reale), ed è predisposto per collegare un broker reale.

## I 4 agenti

| # | Agente | File | Responsabilità |
|---|--------|------|----------------|
| 1 | 🧠 **Analisi** | `agents/analysis.py` | *Cosa* fa il mercato: trend H1/M15, RSI, zone Supply/Demand, spike+conferma, score 0-100 → `Signal` |
| 2 | 🛡️ **Guardiano** | `agents/guardian.py` | *Se* operare: sessione/orari, notizie, ATR, cooldown, limiti giornalieri, circuit breaker → `Permission` |
| 3 | 💰 **Risk** | `agents/risk.py` | *Quanto* rischiare: position sizing, SL, TP1 (M15) e TP2 (H1) → `RiskPlan` |
| 4 | ⚡ **Esecutore** | `agents/executor.py` | *Come* eseguire: apertura ordine, chiusura parziale a TP1, break-even, trailing ATR |

L'**orchestratore** (`orchestrator.py`) li chiama in sequenza su ogni barra:

```
ANALISI → GUARDIANO → RISK → ESECUTORE
   (se uno dei primi tre dice "no", la catena si ferma)
```

## Struttura

```
goldbot_agents/
├── core/        modelli dati, configurazione, indicatori (EMA/RSI/ATR)
├── agents/      i 4 agenti
├── broker/      interfaccia broker + PaperBroker (conto simulato)
├── data/        feed CSV + generatore dati sintetici
├── orchestrator.py
└── main.py      entry point CLI
```

## Uso

```bash
pip install -r requirements.txt

# Dati sintetici (gira subito, nessun file necessario)
python -m goldbot_agents.main

# Modalità e parametri
python -m goldbot_agents.main --mode aggressive --bars 8000 --risk 0.5

# Con un CSV reale (colonne: time,open,high,low,close,volume — timeframe M15)
python -m goldbot_agents.main --csv mio_storico.csv
```

## Test

```bash
python -m pytest tests/ -q
```

## Aggiungere un broker reale

Implementa una sottoclasse di `broker/base.py:Broker` (es. con `MetaTrader5` o
`ccxt`) e passala all'orchestratore al posto di `PaperBroker`. Gli agenti non
cambiano: parlano solo con l'interfaccia astratta.

> ⚠️ Strumento per studio/paper trading. Il trading reale comporta rischio di
> perdita del capitale. Testa a fondo prima di usare denaro vero.
