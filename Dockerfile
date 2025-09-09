# --- STAGE 1: Build the Go application ---
FROM golang:1.22-alpine AS builder-go

WORKDIR /build

# 复制Go模块文件并下载依赖
COPY golang/go.mod golang/go.sum ./
RUN go mod download

# 复制Go源代码
COPY golang/ ./

# 编译Go应用，-ldflags "-w -s" 用于减小体积，CGO_ENABLED=0 用于静态编译
RUN CGO_ENABLED=0 GOOS=linux go build -a -ldflags "-w -s" -o go_app_binary main.go

# --- STAGE 2: Build the final Python application image ---
FROM python:3.10-slim

# 设置工作目录
WORKDIR /app

# ------------------------- 关键修正区域 START -------------------------
# 安装系统依赖
# ADDED: build-essential (编译器), libxml2-dev/libxslt-dev (为 lxml), libmaxminddb-dev (为 geoip)
RUN apt-get update && apt-get install -y --no-install-recommends \
    supervisor \
    xvfb \
    git \
    build-essential \
    libxml2-dev \
    libxslt-dev \
    libmaxminddb-dev \
    && rm -rf /var/lib/apt/lists/*
# ------------------------- 关键修正区域 END ---------------------------

# 复制 supervisor 配置文件
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# 复制 Python 依赖文件并安装
COPY camoufox-py/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 安装 Camoufox 浏览器二进制文件
RUN camoufox fetch

# 从 builder-go 阶段复制编译好的Go程序到最终镜像
COPY --from=builder-go /build/go_app_binary /app/go_app_binary

# 复制 Python 应用源代码
COPY camoufox-py/browser /app/browser
COPY camoufox-py/utils /app/utils
COPY camoufox-py/run_camoufox.py /app/run_camoufox.py

# 暴露Go代理服务的端口
EXPOSE 5345

# 设置容器启动命令，使用 supervisor 启动所有服务
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
