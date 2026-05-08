FROM ubuntu:22.04



# 使用更可靠的方式替换阿里云镜像源，并处理 tzdata
RUN apt-get update && apt-get install -y ca-certificates && \
    printf "deb http://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse\n\
deb http://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse\n\
deb http://mirrors.aliyun.com/ubuntu/ jammy-backports main restricted universe multiverse\n\
deb http://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse" > /etc/apt/sources.list && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    tzdata curl redis-server python3 supervisor && \
    ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

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
