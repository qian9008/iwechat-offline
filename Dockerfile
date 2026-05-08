FROM ubuntu:22.04

# 替换为阿里云镜像源
RUN sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y tzdata && \
    ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata

# 安装基础依赖
RUN apt-get update && apt-get install -y curl ca-certificates redis-server python3 supervisor

# 创建配置目录
RUN mkdir -p /etc/supervisor/conf.d

# 生成 supervisord.conf 配置文件
# 注意：将 .sock 文件路径改到 /tmp 以避免权限和残留问题
RUN echo '[supervisord]' > /etc/supervisor/supervisord.conf && \
    echo 'nodaemon=true' >> /etc/supervisor/supervisord.conf && \
    echo 'user=root' >> /etc/supervisor/supervisord.conf && \
    echo 'loglevel=info' >> /etc/supervisor/supervisord.conf && \
    echo '[unix_http_server]' >> /etc/supervisor/supervisord.conf && \
    echo 'file=/tmp/supervisor.sock' >> /etc/supervisor/supervisord.conf && \
    echo 'chmod=0700' >> /etc/supervisor/supervisord.conf && \
    echo 'username=admin' >> /etc/supervisor/supervisord.conf && \
    echo 'password=yourpassword' >> /etc/supervisor/supervisord.conf && \
    echo '[supervisorctl]' >> /etc/supervisor/supervisord.conf && \
    echo 'serverurl=unix:///tmp/supervisor.sock' >> /etc/supervisor/supervisord.conf && \
    echo 'username=admin' >> /etc/supervisor/supervisord.conf && \
    echo 'password=yourpassword' >> /etc/supervisor/supervisord.conf && \
    echo '[rpcinterface:supervisor]' >> /etc/supervisor/supervisord.conf && \
    echo 'supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface' >> /etc/supervisor/supervisord.conf && \
    echo '[include]' >> /etc/supervisor/supervisord.conf && \
    echo 'files = /etc/supervisor/conf.d/*.conf' >> /etc/supervisor/supervisord.conf

# Redis 配置：增加 --protected-mode no 解决连接被拒问题
RUN echo '[program:redis]' > /etc/supervisor/conf.d/01_redis.conf && \
    echo 'command=redis-server --protected-mode no' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'stderr_logfile=/var/log/redis.err.log' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'stdout_logfile=/var/log/redis.out.log' >> /etc/supervisor/conf.d/01_redis.conf

# Redis GC 配置
RUN echo '[program:redis_gc]' > /etc/supervisor/conf.d/03_redis_gc.conf && \
    echo 'command=/bin/bash /app/scripts/redis_gc_loop.sh' >> /etc/supervisor/conf.d/03_redis_gc.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/03_redis_gc.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/03_redis_gc.conf && \
    echo 'stdout_logfile=/dev/stdout' >> /etc/supervisor/conf.d/03_redis_gc.conf && \
    echo 'stdout_logfile_maxbytes=0' >> /etc/supervisor/conf.d/03_redis_gc.conf && \
    echo 'redirect_stderr=true' >> /etc/supervisor/conf.d/03_redis_gc.conf

# myapp 配置：增加 directory=/app 解决模板找不到的问题
RUN echo '[program:myapp]' > /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'command=/app/myapp' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'directory=/app' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stdout_logfile=/dev/stdout' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stdout_logfile_maxbytes=0' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'redirect_stderr=true' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stdout_events_enabled=true' >> /etc/supervisor/conf.d/99_myapp.conf

LABEL maintainer="exthirteen"
ENV LANG=C.UTF-8
ENV REDIS_GC_CUTOFF_DAYS=3
ENV REDIS_GC_INTERVAL_SECONDS=259200
ENV REDIS_GC_INITIAL_DELAY_SECONDS=120
ENV REDIS_GC_SCAN_COUNT=1000
ENV REDIS_GC_FALLBACK_FLUSHDB=true

WORKDIR /app
ADD myapp /app/myapp
ADD assets /app/assets
ADD static /app/static
ADD scripts /app/scripts

# 确保所有脚本和程序都有执行权限
RUN chmod +x /app/myapp /app/scripts/*.sh /app/scripts/*.py

# 暴露端口
EXPOSE 8849

CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
