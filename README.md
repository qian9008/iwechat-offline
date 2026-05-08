iwechat原作者仓库：[https://github.com/iwechatcom/iwechat](https://github.com/iwechatcom/iwechat)
作者原始描述：iwe项目实现的微信个人号通道，使用ipad协议登录，该协议能获取到wxid，能发送语音条消息，相比itchat协议更稳定。

原仓库限制只能登录2个微信账号，并且现在不允许新机器注册，导致无法获取到ADMIN_KEY，本仓库程序突破了所有使用限制，不限制登录的微信账号个数，不限制新机器注册，并增加了内存自动清理等功能。

不提供Docker部署方法，请自行研究。也不提供ARM版本，我是可以正常使用的，不处理任何issue，不提供任何使用上的帮助，可参考原作者文档：[https://s.apifox.cn/c599d413-b785-4df9-a5f7-482786f96188](https://s.apifox.cn/c599d413-b785-4df9-a5f7-482786f96188) ，请自行正确处理养号、风控。
```bash
docker build -t iwe_offline:v1 .
```

## Redis 自动清理与禁持久化（新增）

容器内 Redis 已改为：

- 启动时删除历史 `dump.rdb` / `appendonly.aof`；
- 以 `--save "" --appendonly no` 启动（不落盘）；
- 重启容器后不会恢复旧缓存数据（避免内存回弹）。

同时新增定时清理任务（Supervisor 常驻进程）：

- 首次延迟执行一次（默认 120 秒）；
- 之后每 72 小时执行一次（默认 259200 秒）；
- 优先删除“可识别时间且早于 3 天前”的 key；
- 若本轮无法识别任何 key 的时间（`classified_keys == 0`），回退执行 `FLUSHDB`（仅当前 `redisConfig.Db`）。

### 清理相关环境变量

- `REDIS_GC_CUTOFF_DAYS=3`
- `REDIS_GC_INTERVAL_SECONDS=259200`
- `REDIS_GC_INITIAL_DELAY_SECONDS=120`
- `REDIS_GC_SCAN_COUNT=1000`
- `REDIS_GC_FALLBACK_FLUSHDB=true`