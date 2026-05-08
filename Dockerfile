FROM ubuntu:22.04

# 替换为阿里云镜像源（解决网络无法下载问题）
RUN sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y tzdata && \
    ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata

# Install curl, ca-certificates, redis, python3, supervisor and mariadb-server-10.6
RUN apt-get update && apt-get install -y curl ca-certificates redis-server python3 supervisor mariadb-server-10.6

# 创建 supervisor 配置目录
RUN mkdir -p /etc/supervisor/conf.d

# 创建 supervisord.conf 配置文件
RUN echo '[supervisord]' > /etc/supervisor/supervisord.conf && \
    echo 'nodaemon=true' >> /etc/supervisor/supervisord.conf && \
    echo 'user=root' >> /etc/supervisor/supervisord.conf && \
    # 设置日志级别为 info，方便排查容器内进程状态
    echo 'loglevel=info' >> /etc/supervisor/supervisord.conf && \
    echo '[unix_http_server]' >> /etc/supervisor/supervisord.conf && \
    echo 'file=/var/run/supervisor.sock' >> /etc/supervisor/supervisord.conf && \
    echo 'chmod=0700' >> /etc/supervisor/supervisord.conf && \
    # 添加身份验证配置
    echo 'username=admin' >> /etc/supervisor/supervisord.conf && \
    echo 'password=yourpassword' >> /etc/supervisor/supervisord.conf && \
    echo '[supervisorctl]' >> /etc/supervisor/supervisord.conf && \
    echo 'serverurl=unix:///var/run/supervisor.sock' >> /etc/supervisor/supervisord.conf && \
    echo 'username=admin' >> /etc/supervisor/supervisord.conf && \
    echo 'password=yourpassword' >> /etc/supervisor/supervisord.conf && \
    echo '[rpcinterface:supervisor]' >> /etc/supervisor/supervisord.conf && \
    echo 'supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface' >> /etc/supervisor/supervisord.conf && \
    echo '[include]' >> /etc/supervisor/supervisord.conf && \
    echo 'files = /etc/supervisor/conf.d/*.conf' >> /etc/supervisor/supervisord.conf

# Add supervisor config for redis
RUN echo '[program:redis]' > /etc/supervisor/conf.d/01_redis.conf && \
    echo 'command=/bin/bash /app/scripts/start-redis.sh' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'stderr_logfile=/var/log/redis.err.log' >> /etc/supervisor/conf.d/01_redis.conf && \
    echo 'stdout_logfile=/var/log/redis.out.log' >> /etc/supervisor/conf.d/01_redis.conf

# Add supervisor config for periodic Redis GC
RUN echo '[program:redis_gc]' > /etc/supervisor/conf.d/03_redis_gc.conf && \
    echo 'command=/bin/bash /app/scripts/redis_gc_loop.sh' >> /etc/supervisor/conf.d/03_redis_gc.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/03_redis_gc.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/03_redis_gc.conf && \
    echo 'startsecs=0' >> /etc/supervisor/conf.d/03_redis_gc.conf && \
    echo 'stdout_logfile=/dev/stdout' >> /etc/supervisor/conf.d/03_redis_gc.conf && \
    echo 'stdout_logfile_maxbytes=0' >> /etc/supervisor/conf.d/03_redis_gc.conf && \
    echo 'redirect_stderr=true' >> /etc/supervisor/conf.d/03_redis_gc.conf

# Add supervisor config for mariadb
RUN echo '[program:mariadb]' > /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'command=/usr/bin/mysqld_safe' >> /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'stderr_logfile=/var/log/mariadb.err.log' >> /etc/supervisor/conf.d/02_mariadb.conf && \
    echo 'stdout_logfile=/var/log/mariadb.out.log' >> /etc/supervisor/conf.d/02_mariadb.conf

# Add supervisor config for myapp，添加参数让 myapp 监听 8849 端口
RUN echo '[program:myapp]' > /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'command=/app/myapp' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stdout_logfile=/dev/stdout' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stdout_logfile_maxbytes=0' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'redirect_stderr=true' >> /etc/supervisor/conf.d/99_myapp.conf && \
    echo 'stdout_events_enabled=true' >> /etc/supervisor/conf.d/99_myapp.conf

# 设置 MariaDB root 密码并创建数据库
RUN service mariadb start && \
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'Iwe@12345678'; FLUSH PRIVILEGES;" && \
    mysql -u root -pIwe@12345678 -e "CREATE DATABASE iwedb;"

LABEL maintainer="exthirteen"
ENV LANG=C.UTF-8
ENV REDIS_GC_CUTOFF_DAYS=3
ENV REDIS_GC_INTERVAL_SECONDS=259200
ENV REDIS_GC_INITIAL_DELAY_SECONDS=120
ENV REDIS_GC_SCAN_COUNT=1000
ENV REDIS_GC_FALLBACK_FLUSHDB=true

WORKDIR /app
# 默认使用离线版本，避免启动时依赖外部验权服务
ADD myapp /app/myapp
ADD assets /app/assets
ADD static /app/static
ADD scripts /app/scripts
RUN chmod +x /app/myapp /app/scripts/*.sh /app/scripts/*.py

# 暴露 8849 端口
EXPOSE 8849
# 修改启动命令，指定配置文件路径
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
