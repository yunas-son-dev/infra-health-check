# Janitor API

Minimal Flask service that serves machine inventory data (IP, location, provider) by Machine ID.

## Run locally

```bash
cd janitor
pip install -r requirements.txt
export JANITOR_API_TOKEN=your-secret-token
python app.py
```

Service listens on `http://localhost:5000`.

## Endpoints

**GET /machines/\<id\>** — fetch a single machine

```bash
curl -H "Authorization: Bearer your-secret-token" http://localhost:5000/machines/SERVER-001
```

**GET /machines?ids=\<id1\>,\<id2\>** — fetch multiple machines

```bash
curl -H "Authorization: Bearer your-secret-token" "http://localhost:5000/machines?ids=SERVER-001,SERVER-002"
```

## Auth

Set `JANITOR_API_TOKEN` as an environment variable (or a Jenkins secret credential).
All requests must include `Authorization: Bearer <token>`.
