FROM ubuntu:22.04

# 1. 基础环境配置
RUN sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y tzdata curl ca-certificates redis-server python3 supervisor && \
    ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata

# 2. 创建目录
RUN mkdir -p /etc/supervisor/conf.d /app

# 3. 生成 Supervisor 主配置（修复了之前的语法错误）
RUN echo '[supervisord]' > /etc/supervisor/supervisord.conf && \
    echo 'nodaemon=true' >> /etc/supervisor/supervisord.conf && \
    echo 'user=root' >> /etc/supervisor/supervisord.conf && \
    echo '[unix_http_server]' >> /etc/supervisor/supervisord.conf && \
    echo 'file=/var/run/supervisor.sock' >> /etc/supervisor/supervisord.conf && \
    echo 'chmod=0700' >> /etc/supervisor/supervisord.conf && \
    echo '[rpcinterface:supervisor]' >> /etc/supervisor/supervisord.conf && \
    echo 'supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface' >> /etc/supervisor/supervisord.conf && \
    echo '[supervisorctl]' >> /etc/supervisor/supervisord.conf && \
    echo 'serverurl=unix:///var/run/supervisor.sock' >> /etc/supervisor/supervisord.conf && \
    echo '[include]' >> /etc/supervisor/supervisord.conf && \
    echo 'files = /etc/supervisor/conf.d/*.conf' >> /etc/supervisor/supervisord.conf

# 4. Redis 相关配置
RUN echo '[program:redis]' > /etc/supervisor/conf.d/01_redis.conf && \
    echo 'command=/usr/bin/redis-server' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/01_redis.conf

# 5. Myapp 配置 (增加 directory=/app 解决路径 Panic 问题)
RUN echo '[program:myapp]' > /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'command=/app/myapp' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'directory=/app' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stdout_logfile=/dev/stdout' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stdout_logfile_maxbytes=0' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'redirect_stderr=true' >> /etc/supervisor/conf.d/99_myapp.conf

# 6. 复制文件
WORKDIR /app
ADD myapp /app/myapp
ADD static /app/static
ADD assets /app/assets
ADD scripts /app/scripts
RUN chmod +x /app/myapp /app/scripts/*.sh /app/scripts/*.py

LABEL maintainer="exthirteen"
ENV LANG=C.UTF-8
EXPOSE 8849

CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
