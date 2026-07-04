# ForexBot Majors — EURUSD & GBPUSD

Bot di trading automatico per **EURUSD** e **GBPUSD**, disponibile in due versioni:

- `ForexBot_Majors.mq5` — Expert Advisor per **MetaTrader 5** (trading automatico reale)
- `ForexBot_Majors.pine` — Strategy per **TradingView** (backtest, alert, visualizzazione)

È l'adattamento forex del motore GoldBot v5.2, ritarato specificamente per le major.

---

## ⚠️ Avvertenza importante (leggila davvero)

**Nessun bot può garantire profitti.** Chiunque prometta guadagni sicuri sta mentendo.
Il trading su forex con leva comporta il rischio concreto di perdere l'intero capitale.

Questo bot è costruito con una logica solida e una gestione del rischio rigorosa,
ma il risultato dipende da mercato, spread, broker ed esecuzione. Regola d'oro:

1. **Backtest** su TradingView / Strategy Tester MT5 su almeno 1-2 anni di storico.
2. **Demo** per almeno 1-2 mesi su conto demo con lo stesso broker che userai live.
3. **Live piccolo**: parti dal capitale minimo e rischio basso solo dopo che demo è positivo.

---

## La strategia (perché dovrebbe funzionare)

L'obiettivo è entrare **solo su setup ad alta probabilità**, non su ogni movimento.
Un trade parte solo quando **tutte** queste condizioni sono vere insieme:

| Componente | Cosa fa |
|---|---|
| **Trend H1 (EMA 21/55)** | Filtro direzionale principale: si opera solo nel verso del trend orario. |
| **Trend M15 (EMA 21/55)** | Conferma di allineamento sul timeframe operativo. |
| **Zone Supply/Demand multi-zona** | Rileva pivot su M15 e traccia fino a 5 zone per lato. Si entra solo sul **retest** di una zona valida (invalidata quando il prezzo la rompe). |
| **Spike + candela di conferma** | Serve un movimento ≥ 0.5 ATR e un corpo candela nella direzione giusta: evita ingressi anticipati. |
| **RSI M15** | Filtro momentum: no acquisti in ipercomprato, no vendite in ipervenduto. |
| **Score 0-100** | Ogni fattore dà punti; il trade parte solo sopra la soglia (60, o 70 in Sessione Estesa). |
| **Filtro sessione** | Solo l'overlap **London/NY (13-17 ora di Roma)** — la finestra più liquida per EUR/GBP. |
| **Filtro ATR (pip)** e **spread** | Niente trade in fasi morte o con spread troppo largo. |
| **Filtro notizie** | Stop intorno a NFP/CPI/ECB/BoE/FOMC. |

### Gestione del rischio (la parte che conta di più)

- **Sizing dinamico**: il lotto è calcolato per rischiare una % fissa dell'equity (default **0.5%**) sulla distanza reale dello stop. Non usi lotti fissi.
- **Stop loss** oltre la zona, con buffer ATR.
- **TP1 parziale (70%)** sulla struttura M15 → incassi presto.
- **Break-even** dopo TP1 → il resto del trade diventa a rischio zero.
- **Trailing ATR** sul residuo → lasci correre i profitti fino al TP2 (struttura H1).
- **Circuit breaker**: se il drawdown dal picco supera il 5%, il bot si mette in pausa X giorni.
- **Limiti giornalieri**: max trade/giorno, max perdita %, max profitto %.

---

## Modalità operative

| Modalità | Orari (Roma) | Score min | Max trade/g | Uso consigliato |
|---|---|---|---|---|
| **Conservativo** (default) | Overlap 13-17 | 60 | 5 | La più selettiva, meno trade ma più puliti. |
| **Sessione Estesa** | 9-20 | **70** | 5 | Più occasioni, ma alza la qualità richiesta. |
| **Aggressivo** | 9-20 | 60 | 10 | Più trade, cooldown ridotto. Solo per chi accetta più varianza. |

---

## Installazione — MetaTrader 5

1. Copia `ForexBot_Majors.mq5` in `MQL5/Experts/` (menu **File → Apri cartella dati**).
2. In MetaEditor premi **Compila** (F7). Deve compilare senza errori.
3. Apri un grafico **EURUSD** (timeframe consigliato **M15**) e trascina l'EA sul grafico.
4. Ripeti su un grafico **GBPUSD** separato.
5. Attiva **AutoTrading** e spunta "Consenti trading algoritmico".

> **Nota timeframe**: l'EA legge trend/zone da H1 e M15 internamente, ma l'ATR dello stop
> usa il timeframe del grafico. Consigliato applicarlo su **M15**.

### Doppia coppia e correlazione (importante)

EURUSD e GBPUSD sono **fortemente correlati** (entrambi contro USD). Due long aperti
insieme = doppia esposizione al dollaro. Per questo il rischio di default è **0.5% per trade**:
con entrambe le coppie attive resti intorno a **~1% di rischio totale**, che è prudente.
Non alzarlo senza aver capito questo punto. Usa lo stesso Magic Number su entrambi i grafici.

---

## Installazione — TradingView

1. Apri **Pine Editor**, incolla `ForexBot_Majors.pine`, premi **Aggiungi al grafico**.
2. Applicalo su **EURUSD** o **GBPUSD**, timeframe **M15**.
3. Usa **Tester di strategia** per il backtest e imposta gli **alert** su `ForexBot BUY/SELL`.

> Il codice usa `request.security` con `[1]` e `lookahead_off`: niente repaint in live.
> Il backtest TradingView non modella lo spread reale: i numeri live saranno più conservativi.

---

## Parametri chiave da tarare

| Parametro | Default | Note |
|---|---|---|
| `Rischio % per trade` | 0.5 | Massimo 1% per chi è esperto. Ricorda: x2 coppie. |
| `ATR minimo in PIP` | 4.0 | Alzalo per filtrare più fasi piatte. |
| `Spread massimo in PIP` | 2.0 | Adatta al tuo broker (major ECB ~0.1-1.0). |
| `Score minimo` | 60 | Più alto = meno trade, più selettivi. |
| `SL buffer ATR` | 0.4 | Più alto = stop più larghi, meno falsi stop. |
| `Trailing ATR mult` | 1.5 | Più alto = trailing più lento, lasci correre di più. |

### Orari notizie (ora di Roma, verifica sempre su un calendario economico)

- **NFP / CPI USA**: ~14:30 (attivo di default)
- **ECB**: ~14:15 nei giorni di riunione (attiva News 2)
- **BoE**: ~13:00 nei giorni di riunione
- **FOMC**: ~20:00 (attiva News 3)

---

## Disclaimer

Software fornito "così com'è", a scopo educativo. Non è consulenza finanziaria.
L'autore non è responsabile di eventuali perdite. Testa sempre in demo prima del live.
