# AI Telegram Signal Server for MT5

This project is a high-performance, Dockerized signal server that bridges Telegram channels with MetaTrader 5 (MT5). It uses the `telethon` library to listen for trading signals in real-time, `OpenAI gpt-4o-mini` to fast and accurately parse unstructured messages into JSON, and a **Raw TCP Socket Server** to deliver signals instanty to MT5.

## Architecture

1.  **Telegram Listener**: Listens to configured channels.
2.  **AI Processor**: OpenAI extracts Symbol, Type, Entry range (min/max), SL, and TP.
3.  **TCP Server**: Broadcasts structured JSON signals to connected TCP clients (MT5 EAs).

## Prerequisites

*   Docker & Docker Compose
*   Python 3.11+ (Local) - *Only needed for initial setup helper*
*   Telegram API Credentials (`API_ID`, `API_HASH`)
*   OpenAI API Key

## Setup Guide

### 1. Configuration

1.  Copy `.env` (it was created with a template) and open it.
2.  Fill in your `TG_API_ID` and `TG_API_HASH`. Get them from [my.telegram.org](https://my.telegram.org/apps).
3.  Fill in your `OPENAI_API_KEY`.
4.  Add the numeric Channel IDs you want to listen to in `TG_CHANNEL_IDS` (comma separated).

### 2. Generate Telegram Session

Since Docker runs in a non-interactive environment, you must generate a session string locally first.

1.  Install dependencies locally:
    ```bash
    pip install telethon python-dotenv
    ```
2.  Run the helper script:
    ```bash
    python generate_session.py
    ```
3.  Follow the prompts to log in with your phone number and code.
4.  Copy the long Session String printed at the end.
5.  Paste it into your `.env` file: `TG_SESSION_STRING=...`

### 3. Run with Docker

Once the `.env` file is fully configured:

```bash
docker-compose up --build -d
```

View logs to ensure it's working:

```bash
docker-compose logs -f
```

## Connecting MT5

In your MetaTrader 5 Expert Advisor (EA), use the `Socket` functions to connect:

*   **Host**: `localhost` (if MT5 is on the same machine) or the Server IP.
*   **Port**: `8888` (Default)

**Logic Features:**

1.  **Entry Range Support (Scalping):**
    *   For signals with entry ranges (e.g., "4233-4240"), the EA opens **Market Orders** when current price is within the `entry_min` to `entry_max` range.
    *   If price is outside the range, **Pending Orders** are placed at range boundaries:
        - BUY: `BuyLimit` at `entry_max` (if price above range) or `BuyStop` at `entry_min` (if price below range)
        - SELL: `SellLimit` at `entry_min` (if price below range) or `SellStop` at `entry_max` (if price above range)
2.  **Pending Order Expiration:**
    *   All pending orders have configurable expiration time (`InpPendingExpiry`, default 30 minutes) suitable for scalping signals.
3.  **Profit-Only Closing:**
    *   Close signals only close positions that are in profit. Positions not in profit remain open with SL/TP protection.
4.  **Minimum Lot Safety:**
    *   If a "Close Partial" signal arrives but your trade is already at the Minimum Lot Size (e.g. 0.01), the EA will **Close Fully** instead of failing.


**Example JSON Payload Sent to MT5:**

1. **New Signal (with Entry Range):**
```json
{
  "symbol": "XAUUSD",
  "action": "NEW",
  "order_type": "SELL",
  "entry_min": 4233.0,
  "entry_max": 4240.0,
  "sl": 4242.0,
  "tp": [4231.0, 4230.0, 4226.0],
  "comment": "Gold Scalping Signal"
}
```

2. **Close Signal (Full):**
```json
{
  "symbol": "XAUUSD",
  "action": "CLOSE",
  "comment": "Take profit"
}
```

3. **Close Partial (e.g., "Close half"):**
```json
{
  "symbol": "XAUUSD",
  "action": "CLOSE_PARTIAL",
  "close_ratio": 0.5
}
```

4. **Close Partial & Breakeven (Composite):**
```json
{
  "symbol": "XAUUSD",
  "action": "CLOSE_PARTIAL_AND_BREAKEVEN",
  "close_ratio": 0.5,
  "comment": "Close profit now and set breakeven"
}
```

5. **Modify SL (e.g., "Move SL to 2025"):**
```json
{
  "symbol": "XAUUSD",
  "action": "MODIFY",
  "sl": 2024.50
}
```

## Troubleshooting

error: **"Interactive authentication required"** inside Docker?
> You skipped Step 2. You MUST generate the `TG_SESSION_STRING` locally and add it to `.env`.

error: **"Connection refused"** in MT5?
> Ensure Docker container is running (`docker ps`) and port `8888` is exposed. Check firewall settings.

## MT5 Expert Advisor Installation

To connect your MetaTrader 5 terminal to this server:

1.  **Locate Files**: Go to `MQL5/Experts/AI_Signal_EA/` in this project.
2.  **Copy to Data Folder**:
    *   Open MT5 -> File -> Open Data Folder.
    *   Navigate to `MQL5/Experts/`.
    *   Copy the entire `AI_Signal_EA` folder into `MQL5/Experts/`.
3.  **Compile**:
    *   Open MetaEditor (F4 in MT5).
    *   Open `MQL5/Experts/AI_Signal_EA/AISignalEA.mq5`.
    *   Click **Compile**.
4.  **Allow WebRequests** (Required for Socket):
    *   In MT5 Options -> Expert Advisors -> Check "Allow WebRequest for listed URL".
    *   Add `127.0.0.1` or `localhost` (though Sockets often bypass this, it's good practice).
5.  **Run**: Drag the EA onto a chart (any chart, e.g., EURUSD M1).
6.  **Inputs**:
    *   **Host**: `127.0.0.1` (or your Cloudflare Tunnel URL).
    *   **Port**: `8888`.
    *   **InpPendingExpiry**: Pending order expiration time in minutes (Default 30 minutes). Suitable for scalping signals.
