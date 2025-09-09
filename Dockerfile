# --- STAGE 1: Build the Go application (此阶段保持不变，高效且正确) ---
FROM golang:1.22-alpine AS builder-go

WORKDIR /build

# 复制Go模块文件并下载依赖
COPY golang/go.mod golang/go.sum ./
RUN go mod download

# 复制Go源代码
COPY golang/ ./

# 编译Go应用
RUN CGO_ENABLED=0 GOOS=linux go build -a -ldflags "-w -s" -o go_app_binary main.go

# --- STAGE 2: Build the final Python application image (关键修正阶段) ---

# 【修正一】: 使用标准的、功能更完整的 python:3.10-bullseye 镜像，而不是 -slim
FROM python:3.10-bullseye

# 设置工作目录
WORKDIR /app

# 【修正二】: 一次性安装所有必要的编译工具和依赖库
# 基于 bullseye 镜像，并补充了 libyaml-dev 以防万一
RUN apt-get update && apt-get install -y --no-install-recommends \
    # 核心编译工具
    build-essential \
    # Python包依赖的C库
    libxml2-dev \
    libxslt-dev \
    libmaxminddb-dev \
    libyaml-dev \
    # 项目运行所需的应用
    supervisor \
    xvfb \
    git \
    && rm -rf /var/lib/apt/lists/*

# 复制 supervisor 配置文件
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# 【修正三】: 在安装依赖前，先升级 pip 工具自身，这是最佳实践
COPY camoufox-py/requirements.txt .
RUN pip install --no-cache-dir --upgrade pip
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

# 设置容器启动命令
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
