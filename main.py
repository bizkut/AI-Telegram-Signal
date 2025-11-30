import os
import asyncio
import logging
import sys
from dotenv import load_dotenv
from telethon import TelegramClient, events
from telethon.sessions import StringSession

from signal_processor import SignalProcessor
from tcp_server import TCPSignalServer

# Configure Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)

# Load Environment Variables
load_dotenv()

API_ID = os.getenv("TG_API_ID")
API_HASH = os.getenv("TG_API_HASH")
SESSION_STRING = os.getenv("TG_SESSION_STRING")
CHANNEL_IDS_RAW = os.getenv("TG_CHANNEL_IDS", "")
SERVER_HOST = os.getenv("SERVER_HOST", "0.0.0.0")
SERVER_PORT = int(os.getenv("SERVER_PORT", 8888))

# Parse Channel IDs
try:
    CHANNEL_IDS = [int(x.strip()) for x in CHANNEL_IDS_RAW.split(",") if x.strip()]
except ValueError:
    logger.error("Invalid TG_CHANNEL_IDS format. Must be comma-separated integers.")
    sys.exit(1)

if not all([API_ID, API_HASH, SESSION_STRING]):
    logger.error("Missing required Telegram variables (API_ID, API_HASH, SESSION_STRING).")
    sys.exit(1)

# Initialize Components
signal_processor = SignalProcessor()
tcp_server = TCPSignalServer(SERVER_HOST, SERVER_PORT)
client = TelegramClient(StringSession(SESSION_STRING), int(API_ID), API_HASH)

@client.on(events.NewMessage(chats=CHANNEL_IDS))
async def handle_new_message(event):
    """
    Event handler for new Telegram messages.
    """
    message_text = event.message.message
    if not message_text:
        return
        
    logger.info(f"Received message from {event.chat_id}: \n{message_text[:50]}...") # Log first 50 chars

    # Get Reply Context if available
    reply_text = None
    if event.is_reply:
        reply_message = await event.get_reply_message()
        if reply_message and reply_message.message:
            reply_text = reply_message.message
            logger.info(f"Found Reply Context: {reply_text[:50]}...")

    # Process Signal
    signal_json = await signal_processor.process_signal(message_text, reply_context=reply_text)
    
    if signal_json:
        logger.info(f"Valid Signal Extracted: {signal_json}")
        await tcp_server.broadcast(signal_json)
    else:
        logger.info("No valid signal found in message.")

async def main():
    logger.info("Starting AI Signal Server...")
    
    # Start TCP Server task
    server_task = asyncio.create_task(tcp_server.start())
    
    # Start Telegram Client
    logger.info("Connecting to Telegram...")
    await client.start()
    logger.info("Telegram Client Connected & Listening!")

    try:
        # Run until disconnected
        await asyncio.gather(
            server_task,
            client.run_until_disconnected()
        )
    except KeyboardInterrupt:
        logger.info("Stopping server...")
    finally:
        await client.disconnect()

if __name__ == "__main__":
    asyncio.run(main())
