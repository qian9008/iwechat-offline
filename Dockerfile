FROM ubuntu:22.04

# 1. 基础环境
RUN sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y tzdata curl ca-certificates redis-server python3 supervisor && \
    ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata

# 2. 准备目录
WORKDIR /app
RUN mkdir -p /etc/supervisor/conf.d

# 3. 写入 Supervisor 配置 (强制指定 directory=/app)
RUN echo '[supervisord]\nnodaemon=true\nuser=root\n\n[unix_http_server]\nfile=/tmp/supervisor.sock\nchmod=0700\n\n[supervisorctl]\nserverurl=unix:///tmp/supervisor.sock\n\n[rpcinterface:supervisor]\nsupervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface\n\n[include]\nfiles = /etc/supervisor/conf.d/*.conf' > /etc/supervisor/supervisord.conf

RUN echo '[program:redis]\ncommand=redis-server --protected-mode no\nautostart=true\nautorestart=true' > /etc/supervisor/conf.d/01_redis.conf

# 关键：这里必须有 directory=/app
RUN echo '[program:myapp]\ncommand=/app/myapp\ndirectory=/app\nautostart=true\nautorestart=true\nstdout_logfile=/dev/stdout\nstdout_logfile_maxbytes=0\nredirect_stderr=true' > /etc/supervisor/conf.d/99_myapp.conf

# 4. 复制文件
COPY myapp /app/myapp
COPY assets /app/assets
COPY static /app/static
COPY scripts /app/scripts

# 5. 路径补丁 (重点)
RUN chmod +x /app/myapp /app/scripts/*.sh /app/scripts/*.py

# 补丁 A: 建立根目录软链接。如果程序找 /static 而不是 static/，此操作可救命。
RUN ln -s /app/static /static || true

# 补丁 B: 强制兼容后缀。将 .tmpl 复制为 .html，确保 LoadHTMLGlob 匹配成功。
RUN if [ -d "/app/static/templates" ]; then \
    cd /app/static/templates && \
    for f in *.tmpl; do cp "$f" "${f%.tmpl}.html" 2>/dev/null || true; done; \
    fi

# 6. 环境设置
LABEL maintainer="exthirteen"
ENV LANG=C.UTF-8
EXPOSE 8849

CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
