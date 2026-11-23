FROM python:3.13-slim
RUN pip install --no-cache-dir cryptography==44.0.0
COPY server.py /app/server.py
WORKDIR /app
CMD ["python", "server.py"]
