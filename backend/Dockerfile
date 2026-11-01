FROM python:3.12-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN useradd --create-home --uid 10001 app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY --chown=app:app . .
RUN sed -i 's/\r$//' scripts/entrypoint.sh scripts/container-entrypoint.sh \
    && chmod +x scripts/entrypoint.sh scripts/container-entrypoint.sh

USER app

EXPOSE 8000

ENTRYPOINT ["./scripts/container-entrypoint.sh"]
CMD ["app.reports.lambda_handler.handler"]
