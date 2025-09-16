# syntax=docker/dockerfile:1.6

# --- STAGE 1: Build the Go application ---
    FROM golang:1.22-alpine AS builder-go
    WORKDIR /build
    
    # Alpine 换国内源
    RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories
    RUN apk add --no-cache ca-certificates && update-ca-certificates
    
    # Go 国内代理与 sumdb
    ENV GOPROXY=https://goproxy.cn,direct \
        GOSUMDB=sum.golang.google.cn
    
    COPY golang/go.mod golang/go.sum ./
    RUN --mount=type=cache,target=/go/pkg/mod \
        --mount=type=cache,target=/root/.cache/go-build \
        go mod download
    
    COPY golang/ ./
    RUN --mount=type=cache,target=/go/pkg/mod \
        --mount=type=cache,target=/root/.cache/go-build \
        CGO_ENABLED=0 GOOS=linux go build -a -ldflags "-w -s" -o go_app_binary main.go
    
    
    # --- STAGE 2: Python application image ---
    FROM python:3.11-bullseye
    WORKDIR /app
    
    # APT 换国内源 + 重试
    RUN bash -lc 'set -e; \
      printf "Acquire::Retries \"5\";\nAcquire::ForceIPv4 \"true\";\n" > /etc/apt/apt.conf.d/99resilient; \
      sed -ri "s|http://deb.debian.org/debian|https://mirrors.tuna.tsinghua.edu.cn/debian|g" /etc/apt/sources.list; \
      sed -ri "s|http://security.debian.org/debian-security|https://mirrors.tuna.tsinghua.edu.cn/debian-security|g" /etc/apt/sources.list; \
      apt-get update; \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential libxml2-dev libxslt-dev libmaxminddb-dev libyaml-dev \
        supervisor xvfb git libgtk-3-0 libasound2 libdbus-glib-1-2 libxt6 ca-certificates; \
      rm -rf /var/lib/apt/lists/*'
    
    # pip 使用国内源 + 允许缓存（供 BuildKit 复用）
    ENV PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple \
        PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn \
        PIP_DEFAULT_TIMEOUT=180 \
        PIP_DISABLE_PIP_VERSION_CHECK=1
    
    COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
    COPY camoufox-py/requirements.txt .
    
    RUN --mount=type=cache,target=/root/.cache/pip \
        python -m pip install --upgrade pip setuptools wheel
    
    RUN --mount=type=cache,target=/root/.cache/pip \
        pip install --prefer-binary -r requirements.txt
    
    # 尝试缓存 camoufox 下载（若它走 XDG cache）
    ENV XDG_CACHE_HOME=/root/.cache
    RUN --mount=type=cache,target=/root/.cache \
        camoufox fetch
    
    COPY --from=builder-go /build/go_app_binary /app/go_app_binary
    COPY camoufox-py/browser /app/browser
    COPY camoufox-py/utils /app/utils
    COPY camoufox-py/run_camoufox.py /app/run_camoufox.py
    
    EXPOSE 5345
    CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]