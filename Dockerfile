FROM ubuntu:22.04

# 设置非交互模式
ENV DEBIAN_FRONTEND=noninteractive

# 1. 仅安装必要的运行库（去掉了数据库和 Redis 服务端）
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    python3 \
    supervisor \
    tzdata \
    && ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && dpkg-reconfigure -f noninteractive tzdata \
    && rm -rf /var/lib/apt/lists/*

# 2. 配置 Supervisor（仅保留管理 myapp 的部分）
RUN mkdir -p /etc/supervisor/conf.d /var/log/supervisor
COPY <<EOF /etc/supervisor/supervisord.conf
[supervisord]
nodaemon=true
user=root
loglevel=info
logfile=/var/log/supervisor/supervisord.log

[include]
files = /etc/supervisor/conf.d/*.conf
EOF

# 3. 创建 myapp 的进程管理配置
# 注意：这里我们假设你的程序支持通过命令行参数或环境变量读取配置
RUN echo '[program:myapp]\n\
command=/app/myapp\n\
autostart=true\n\
autorestart=true\n\
stdout_logfile=/dev/stdout\n\
stdout_logfile_maxbytes=0\n\
redirect_stderr=true' > /etc/supervisor/conf.d/myapp.conf

# 4. 设置工作目录
WORKDIR /app

# 5. 复制程序文件（这些文件需在 Git 仓库根目录）
COPY myapp /app/myapp
COPY assets /app/assets
COPY static /app/static
COPY scripts /app/scripts
RUN chmod +x /app/myapp /app/scripts/*.sh /app/scripts/*.py

LABEL maintainer="exthirteen"
ENV LANG=C.UTF-8

# 暴露程序端口
EXPOSE 8849

CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
