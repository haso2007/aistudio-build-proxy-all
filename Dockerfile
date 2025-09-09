# --- STAGE 1: Build the Go application (此阶段保持不变) ---
FROM golang:1.22-alpine AS builder-go

WORKDIR /build
COPY golang/go.mod golang/go.sum ./
RUN go mod download
COPY golang/ ./
RUN CGO_ENABLED=0 GOOS=linux go build -a -ldflags "-w -s" -o go_app_binary main.go


# --- STAGE 2: Build the final Python application image (关键修正阶段) ---

# 【最终修正】: 将 Python 版本从 3.10 升级到 3.11，以满足 numpy==2.3.0 的要求
FROM python:3.11-bullseye

WORKDIR /app

# 安装所有必要的编译工具和依赖库 (这些都是正确的，保持不变)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libxml2-dev \
    libxslt-dev \
    libmaxminddb-dev \
    libyaml-dev \
    supervisor \
    xvfb \
    git \
    && rm -rf /var/lib/apt/lists/*

# 复制 supervisor 配置文件
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# 升级 pip 并安装依赖 (保持不变)
COPY camoufox-py/requirements.txt .
RUN pip install --no-cache-dir --upgrade pip
RUN pip install --no-cache-dir -r requirements.txt

# 安装 Camoufox 浏览器二进制文件
RUN camoufox fetch

# 从 builder-go 阶段复制编译好的Go程序
COPY --from=builder-go /build/go_app_binary /app/go_app_binary

# 复制 Python 应用源代码
COPY camoufox-py/browser /app/browser
COPY camoufox-py/utils /app/utils
COPY camoufox-py/run_camoufox.py /app/run_camoufox.py

# 暴露端口
EXPOSE 5345

# 设置启动命令
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
