import json
import os
from openai import AsyncOpenAI

class SignalProcessor:
    def __init__(self):
        api_key = os.getenv("OPENAI_API_KEY")
        if not api_key:
            raise ValueError("OPENAI_API_KEY not found in environment variables")
        self.client = AsyncOpenAI(api_key=api_key)

    async def process_signal(self, text: str, reply_context: str = None):
        """
        Analyzes the text using OpenAI o3-mini to extract trading signal details.
        
        Args:
            text: The content of the new message.
            reply_context: The content of the original message being replied to (optional).
            
        Returns:
            A JSON string with the structured signal or None if no valid signal is found.
        """
        system_prompt = (
            "You are an expert Forex Signal Parser. Your job is to extract trading signal details "
            "from unstructured telegram messages and output them in strict JSON format.\n"
            "The JSON structure must be:\n"
            "{\n"
            '  "symbol": "string (e.g., XAUUSD, EURUSD)",\n'
            '  "action": "string (NEW, CLOSE, CLOSE_PARTIAL, MODIFY, CLOSE_PARTIAL_AND_BREAKEVEN)",\n'
            '  "order_type": "string (BUY, SELL, BUY LIMIT, SELL LIMIT, null for CLOSE/MODIFY)",\n'
            '  "entry_min": "float (lower bound of entry range, or single entry price)",\n'
            '  "entry_max": "float (upper bound of entry range, or same as entry_min if single price)",\n'
            '  "sl": "float (Stop Loss, or null)",\n'
            '  "tp": [float] (Array of Take Profit levels),\n'
            '  "close_ratio": "float (0.0 to 1.0, e.g. 0.5 for half close, 1.0 for full close)",\n'
            '  "comment": "string (Any additional info)"\n'
            "}\n"
            "Rules:\n"
            "1. Messages can be NEW signals or UPDATES to previous signals (context provided).\n"
            "2. For NEW signals: Action is 'NEW'. Extract Entry, SL, TP.\n"
            "3. For CLOSE signals:\n"
            "   - If 'Close now', 'Close full': Action is 'CLOSE'.\n"
            "   - If 'Close half', 'Partial close': Action is 'CLOSE_PARTIAL', close_ratio=0.5.\n"
            "   - If 'Close profit AND set breakeven' (Composite): Action is 'CLOSE_PARTIAL_AND_BREAKEVEN', close_ratio=0.5.\n"
            "   - Use the Context message to identify the Symbol if not present in the new message.\n"
            "4. For MODIFY signals (e.g. 'Move SL', 'TP hit', 'Set Breakeven'):\n"
            "   - If 'Set Breakeven' (without closing): Action is 'MODIFY', set sl_is_breakeven=true (or just ensure logic handles it downstream), but better: Action 'MODIFY', comment 'BREAKEVEN'.\n"
            "   - Action is 'MODIFY'. Extract new SL or TP.\n"
            "   - Use Context to identify Symbol.\n"
            "5. If multiple TPs are given, list them.\n"
            "6. If Entry is a range (e.g., '4233-4240'), set entry_min to the lower value and entry_max to the upper value.\n"
            "   If Entry is a single price, set both entry_min and entry_max to that price.\n"
            "7. Output ONLY raw JSON. Return null if not a trading instruction."
        )

        user_content = f"New Message: {text}"
        if reply_context:
            user_content += f"\n\nContext (Original Signal): {reply_context}"

        try:
            response = await self.client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_content}
                ]
            )

            content = response.choices[0].message.content.strip()
            
            # Remove markdown code blocks
            if content.startswith("```json"):
                content = content[7:]
            if content.endswith("```"):
                content = content[:-3]
            content = content.strip()

            if content.lower() == "null":
                return None

            # Validate JSON
            signal_data = json.loads(content)
            
            # Basic validation
            if not signal_data.get("symbol") or not signal_data.get("action"):
                return None
            
            # Normalize casing
            if signal_data.get("symbol"):
                signal_data["symbol"] = signal_data["symbol"].upper()
                
            return json.dumps(signal_data)

        except Exception as e:
            print(f"Error processing signal: {e}")
            return None
