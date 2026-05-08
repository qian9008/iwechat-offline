FROM ubuntu:22.04

# 1. 基础环境与时区
RUN sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y tzdata curl ca-certificates redis-server python3 supervisor && \
    ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata

# 2. 准备目录结构
WORKDIR /app
RUN mkdir -p /etc/supervisor/conf.d

# 3. 写入全量 Supervisor 配置 (一次性写入，避免格式乱序)
RUN echo '[supervisord]\nnodaemon=true\nuser=root\n\n[unix_http_server]\nfile=/tmp/supervisor.sock\nchmod=0700\n\n[supervisorctl]\nserverurl=unix:///tmp/supervisor.sock\n\n[rpcinterface:supervisor]\nsupervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface\n\n[include]\nfiles = /etc/supervisor/conf.d/*.conf' > /etc/supervisor/supervisord.conf

# Redis 配置
RUN echo '[program:redis]\ncommand=redis-server --protected-mode no\nautostart=true\nautorestart=true' > /etc/supervisor/conf.d/01_redis.conf

# myapp 配置 - 增加 directory 参数并使用 bash 启动以增强兼容性
RUN echo '[program:myapp]\ncommand=/app/myapp\ndirectory=/app\nautostart=true\nautorestart=true\nstdout_logfile=/dev/stdout\nstdout_logfile_maxbytes=0\nredirect_stderr=true' > /etc/supervisor/conf.d/99_myapp.conf

# 4. 复制项目文件
# 请确保这些文件在你的 GitHub 仓库根目录下
COPY myapp /app/myapp
COPY assets /app/assets
COPY static /app/static
COPY scripts /app/scripts

# 5. 权限与路径补全
RUN chmod +x /app/myapp /app/scripts/*.sh /app/scripts/*.py

# 【关键点 A】创建根目录软链接，防止程序去找 /static 而不是 ./static
RUN ln -s /app/static /static || true

# 【关键点 B】处理模板后缀名，把 .tmpl 全部复制一份成 .html
RUN if [ -d "/app/static/templates" ]; then \
    cd /app/static/templates && \
    for f in *.tmpl; do cp "$f" "${f%.tmpl}.html" 2>/dev/null || true; done; \
    fi

# 6. 环境参数
LABEL maintainer="exthirteen"
ENV LANG=C.UTF-8
EXPOSE 8849

CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
