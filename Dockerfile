FROM python:3.12-slim
ARG VERSION=dev
ARG PORT=8000
ENV APP_VERSION=$VERSION APP_PORT=$PORT PYTHONUNBUFFERED=1
RUN useradd -r app
WORKDIR /app
COPY app.py .
USER app
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')"
CMD ["python", "app.py"]
