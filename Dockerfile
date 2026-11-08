FROM python:3.11-slim-bookworm

LABEL maintainer="peaceiris"

WORKDIR /docs

COPY requirements.txt .
RUN python3 -m pip install --no-cache-dir "pip==26.2.1" && \
    python3 -m pip install --no-cache-dir -r requirements.txt && \
    python3 -m pip check

COPY . .

EXPOSE 8000

CMD ["mkdocs", "serve", "--dev-addr=0.0.0.0:8000"]
