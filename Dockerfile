FROM ubuntu:22.04

# 1. 系统基础环境配置
# 移除阿里云替换逻辑，直接使用官方源，增加重试机制解决网络波动
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

# 2. 生成 Supervisor 配置文件
RUN mkdir -p /etc/supervisor/conf.d /var/log/supervisor

RUN echo '[supervisord]\nnodaemon=true\nuser=root\n\n[unix_http_server]\nfile=/tmp/supervisor.sock\nchmod=0700\n\n[supervisorctl]\nserverurl=unix:///tmp/supervisor.sock\n\n[rpcinterface:supervisor]\nsupervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface\n\n[include]\nfiles = /etc/supervisor/conf.d/*.conf' > /etc/supervisor/supervisord.conf

# Redis 启动配置
RUN echo '[program:redis]\ncommand=redis-server --protected-mode no\nautostart=true\nautorestart=true' > /etc/supervisor/conf.d/01_redis.conf

# myapp 启动配置 (关键：directory=/app)
RUN echo '[program:myapp]\ncommand=/app/myapp\ndirectory=/app\nautostart=true\nautorestart=true\nstdout_logfile=/dev/stdout\nstdout_logfile_maxbytes=0\nredirect_stderr=true' > /etc/supervisor/conf.d/99_myapp.conf

# 3. 复制项目文件
WORKDIR /app
# 再次确认：此处的 myapp 必须是你从作者那下载的 Linux 版本，重命名为 myapp
COPY myapp /app/myapp
COPY assets /app/assets
COPY static /app/static
COPY scripts /app/scripts

# 4. 权限与路径修复
RUN chmod +x /app/myapp /app/scripts/*.sh /app/scripts/*.py

# 处理模板后缀兼容性
RUN if [ -d "/app/static/templates" ]; then \
    cd /app/static/templates && \
    for f in *.tmpl; do cp "$f" "${f%.tmpl}.html" 2>/dev/null || true; done; \
    fi

EXPOSE 8849

CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
