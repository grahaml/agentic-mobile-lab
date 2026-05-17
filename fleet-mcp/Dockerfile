FROM python:3.12-slim

WORKDIR /app

RUN pip install --no-cache-dir mcp httpx uvicorn

COPY server.py .

# Expose SSE port
EXPOSE 8000

# Start as SSE server
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000"]
