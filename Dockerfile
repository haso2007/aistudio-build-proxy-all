# --- STAGE 1: Build the Go application ---
FROM golang:1.22-alpine AS builder-go
WORKDIR /build

RUN apk add --no-cache ca-certificates && update-ca-certificates

# 可选：允许用 --build-arg 覆盖；不传则使用 RUN 中的默认值
ARG GOPROXY
ARG GOSUMDB

COPY golang/go.mod golang/go.sum ./
# 关键：使用默认值兜底，避免空值
RUN go env -w \
    GOPROXY=${GOPROXY:-https://goproxy.cn,direct} \
    GOSUMDB=${GOSUMDB:-sum.golang.org} \
  && go mod download

COPY golang/ ./
RUN CGO_ENABLED=0 GOOS=linux go build -a -ldflags "-w -s" -o go_app_binary main.go

# --- STAGE 2: Build the final Python application image ---
FROM python:3.11-bullseye
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libxml2-dev \
    libxslt-dev \
    libmaxminddb-dev \
    libyaml-dev \
    supervisor \
    xvfb \
    git \
    libgtk-3-0 \
    libasound2 \
    libdbus-glib-1-2 \
    libxt6 \
    && rm -rf /var/lib/apt/lists/*
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY camoufox-py/requirements.txt .
RUN pip install --no-cache-dir --upgrade pip
RUN pip install --no-cache-dir -r requirements.txt
RUN camoufox fetch
COPY --from=builder-go /build/go_app_binary /app/go_app_binary
COPY camoufox-py/browser /app/browser
COPY camoufox-py/utils /app/utils
COPY camoufox-py/run_camoufox.py /app/run_camoufox.py
EXPOSE 5345
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
