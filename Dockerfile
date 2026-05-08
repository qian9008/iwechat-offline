FROM ubuntu:22.04

# 1. 基础环境安装 (移除 sed 换源逻辑，直接使用官方源)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    tzdata \
    curl \
    ca-certificates \
    redis-server \
    python3 \
    supervisor && \
    ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone && \
    dpkg-reconfigure -f noninteractive tzdata && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 2. 准备目录
WORKDIR /app
RUN mkdir -p /etc/supervisor/conf.d

# 3. 写入 Supervisor 配置 (核心修复：增加 directory=/app)
RUN echo '[supervisord]\nnodaemon=true\nuser=root\n\n[unix_http_server]\nfile=/tmp/supervisor.sock\nchmod=0700\n\n[supervisorctl]\nserverurl=unix:///tmp/supervisor.sock\n\n[rpcinterface:supervisor]\nsupervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface\n\n[include]\nfiles = /etc/supervisor/conf.d/*.conf' > /etc/supervisor/supervisord.conf

# Redis 配置
RUN echo '[program:redis]\ncommand=redis-server --protected-mode no\nautostart=true\nautorestart=true' > /etc/supervisor/conf.d/01_redis.conf

# 服务端程序配置 (myapp 是指镜像里的服务端，directory=/app 解决模板路径 panic)
RUN echo '[program:myapp]\ncommand=/app/myapp\ndirectory=/app\nautostart=true\nautorestart=true\nstdout_logfile=/dev/stdout\nstdout_logfile_maxbytes=0\nredirect_stderr=true' > /etc/supervisor/conf.d/99_myapp.conf

# 4. 复制服务端文件
# 注意：这里的 myapp 是你通过 GitHub Actions 编译出来的 Linux 服务端
COPY myapp /app/myapp
COPY assets /app/assets
COPY static /app/static
COPY scripts /app/scripts

# 5. 权限与路径补丁
RUN chmod +x /app/myapp /app/scripts/*.sh /app/scripts/*.py

# 处理模板后缀兼容性：把 .tmpl 复制为 .html，防止程序匹配不到文件
RUN if [ -d "/app/static/templates" ]; then \
    cd /app/static/templates && \
    for f in *.tmpl; do cp "$f" "${f%.tmpl}.html" 2>/dev/null || true; done; \
    fi

EXPOSE 8849

CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
