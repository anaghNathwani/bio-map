# Security

## Authentication

- Passwords are hashed with **bcrypt** (via `passlib`) — never stored in plaintext
- JWTs are signed with **HS256** using a `SECRET_KEY` loaded from environment variables
- Tokens expire after **30 days** by default (configurable)
- No refresh token in v1.0 — users re-authenticate on expiry

### Hardening checklist

- [ ] Set `SECRET_KEY` to a cryptographically random 64-character string in production
- [ ] Rotate `SECRET_KEY` periodically (invalidates all existing sessions)
- [ ] Enforce HTTPS — iOS ATS blocks plain HTTP in production builds
- [ ] Rate-limit `/auth/register` and `/auth/login` (nginx `limit_req` or a FastAPI middleware)

---

## File Upload Safety

Photo uploads are processed by:

1. **Content-type check** — only `image/jpeg` and `image/png` accepted
2. **Pillow thumbnail generation** — re-encodes the image; neutralises embedded script payloads
3. **UUID key** — filenames are UUID-based, preventing path traversal

The original image bytes are not executed or passed to any shell command.

**Recommended additional measure (v1.1):** Run uploaded images through a virus scanner (e.g. ClamAV) before storing.

---

## API Security

### SQL injection

SQLAlchemy's ORM parameterises all queries. Raw SQL is not used. PostGIS function calls (`ST_MakePoint`, `ST_Within`) use SQLAlchemy expressions, not string interpolation.

### CORS

The current CORS configuration allows all origins (`allow_origins=["*"]`). This is acceptable for development. In production:

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://app.birdmap.app"],
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type"],
)
```

### Input validation

FastAPI + Pydantic validates all JSON request bodies. Type errors return `422 Unprocessable Entity` before business logic runs.

### Authorization

All write operations (`POST /sightings`, `POST /annotations`) require a valid JWT. Read operations (`GET /sightings`, `GET /leaderboard`) are public — this is intentional for biosphere mapping use cases.

---

## Infrastructure Security

### Secrets management

- All secrets are in `backend/.env` — never committed to Git (`.env` is in `.gitignore`)
- Use a secrets manager (AWS Secrets Manager, Vault, Doppler) for production
- MinIO credentials should be rotated from the defaults before production deployment

### Network isolation

In Docker Compose, PostgreSQL and MinIO are not exposed externally — they are only accessible on the internal Docker network. The FastAPI container is the only service behind the reverse proxy.

### MinIO access control

In production, create a dedicated MinIO user with write-only access to `birdmap-photos` and `birdmap-models`, rather than using the root `minioadmin` credentials.

```bash
mc admin user add local birdmap-api STRONG_PASSWORD
mc admin policy attach local readwrite --user birdmap-api
```

---

## Responsible Disclosure

To report a security vulnerability, email security@birdmap.app. Do not open a public GitHub issue for security bugs. We aim to respond within 48 hours and patch critical vulnerabilities within 7 days.
