import asyncio
import logging

class TCPSignalServer:
    def __init__(self, host, port):
        self.host = host
        self.port = port
        self.clients = set()
        self.server = None

    async def handle_client(self, reader, writer):
        addr = writer.get_extra_info('peername')
        logging.info(f"New connection from {addr}")
        self.clients.add(writer)

        try:
            while True:
                # Keep connection alive and read any incoming data (heartbeats, etc.)
                data = await reader.read(100)
                if not data:
                    break
        except asyncio.CancelledError:
            pass
        except Exception as e:
            logging.error(f"Error handling client {addr}: {e}")
        finally:
            logging.info(f"Connection closed from {addr}")
            self.clients.discard(writer)
            writer.close()
            await writer.wait_closed()

    async def start(self):
        self.server = await asyncio.start_server(
            self.handle_client, self.host, self.port
        )
        addr = self.server.sockets[0].getsockname()
        logging.info(f"TCP Signal Server serving on {addr}")

        async with self.server:
            await self.server.serve_forever()

    async def broadcast(self, message: str):
        """Sends a message to all connected clients."""
        if not self.clients:
            logging.warning("No clients connected. Signal not sent.")
            return

        logging.info(f"Broadcasting signal to {len(self.clients)} clients: {message}")
        # Add newline delimiter for socket protocol
        data = (message + "\n").encode()
        
        for writer in list(self.clients):
            try:
                writer.write(data)
                await writer.drain()
            except Exception as e:
                logging.error(f"Failed to send to client: {e}")
                self.clients.discard(writer)
