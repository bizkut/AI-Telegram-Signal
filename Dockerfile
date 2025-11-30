FROM python:3.11-slim

WORKDIR /app

# Upgrade pip and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source code
COPY . .

# Expose the TCP server port
EXPOSE 8888

# Run the application
CMD ["python", "main.py"]
