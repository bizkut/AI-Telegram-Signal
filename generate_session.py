import asyncio
import os
from telethon import TelegramClient
from telethon.sessions import StringSession
from dotenv import load_dotenv

# Load .env file
load_dotenv()

api_id = os.getenv("TG_API_ID")
api_hash = os.getenv("TG_API_HASH")

if not api_id or not api_hash:
    print("Error: TG_API_ID or TG_API_HASH not found in .env file.")
    print("Please fill in your .env file first.")
    exit(1)

print("Starting Telegram Client login...")
print("Follow the instructions to log in. Once successful, a Session String will be printed.")

async def main():
    async with TelegramClient(StringSession(), int(api_id), api_hash) as client:
        print("\nSUCCESS! Here is your Session String:\n")
        print(client.session.save())
        print("\nCopy the string above and paste it into your .env file as TG_SESSION_STRING")

if __name__ == '__main__':
    asyncio.run(main())
