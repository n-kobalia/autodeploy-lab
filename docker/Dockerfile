# ── Stage 1: Builder ────────────────────────────────────────────────
# We use a full Python image to install dependencies.
# This stage is temporary — it won't exist in the final image.
FROM python:3.11-slim AS builder

WORKDIR /build

COPY app/requirements.txt .

RUN pip install --upgrade pip && \
    pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: Final image ─────────────────────────────────────────────
# We start fresh from a clean slim image.
# We only copy in the installed packages from the builder — not pip, not cache.
FROM python:3.11-slim

WORKDIR /app

# Copy installed packages from the builder stage
COPY --from=builder /install /usr/local

# Copy only the application code
COPY app/app.py .
COPY app/templates/ templates/
COPY app/migrations/ migrations/

# Environment variables with safe defaults
ENV PORT=5000
ENV ENVIRONMENT=production

# Tell Docker this container listens on port 5000
EXPOSE 5000

# The command that runs when the container starts
CMD ["python", "app.py"]