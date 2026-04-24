<h1 align="center">site-bootstrap</h1>
<p align="center">
  <b>一条命令把静态站或 Node 应用部署到你自己的 VPS · 带 Cloudflare DNS、nginx、Let's Encrypt 自动化</b><br/>
  <sub>One command to ship a static or Node site to your own VPS — with Cloudflare DNS, nginx, and Let's Encrypt wired in.</sub>
</p>

<p align="center">
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square" alt="MIT"/></a>
  <img src="https://img.shields.io/badge/shell-bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white" alt="Bash"/>
  <img src="https://img.shields.io/badge/dependencies-ssh%20%2B%20rsync%20%2B%20jq-2EA043?style=flat-square" alt="Dependencies"/>
  <img src="https://img.shields.io/badge/status-v0.1.0-0A66C2?style=flat-square" alt="Version"/>
</p>

---

## 它解决什么问题 · What it solves

每次给一个新域名做上线，你本来要手动做这些事：

1. 去 Cloudflare 后台加 A 记录
2. rsync 代码 / 跑 build
3. 在服务器上写一份 nginx 配置
4. `certbot --nginx -d ...`
5. 重载、curl 验证、回头发现 DNS 还没传播
6. 下次要回滚的时候——**上一版早就没了**

`site-bootstrap` 把这六步塞进一条命令，还顺手保留了上一版的快照方便 `rollback`。脚本全部是 Bash，依赖只有 `ssh`、`rsync`、`jq`、`curl`——服务器上只要 nginx + certbot。**没有 agent、没有 daemon、没有专有协议。**

---

## 30 秒跑通 · 30-second demo

```bash
# 1. 装
curl -fsSL https://raw.githubusercontent.com/tianmind-studio/site-bootstrap/main/install.sh | bash

# 2. 脚手架（交互式问你域名、服务器、站型）
site-bootstrap new my-blog
cd my-blog

# 3. 填 Cloudflare 凭据（可选；没填就跳过 DNS 自动化）
cp .env.example .env
# 编辑 .env：CF_API_TOKEN / CF_ZONE_ID

# 4. 部署
site-bootstrap deploy

# 5. 如果上一版出问题
site-bootstrap rollback
```

---

## 命令速查 · Command reference

| 命令 | 作用 |
|------|------|
| `site-bootstrap new <name>` | 交互式生成 `site.yaml` 和项目骨架 |
| `site-bootstrap deploy` | 读取 `site.yaml` 执行完整部署流水线 |
| `site-bootstrap dns add <fqdn> <ip> [--proxied]` | 单独调用 Cloudflare 加/改 A 记录 |
| `site-bootstrap dns list` | 列出当前 Zone 的全部 A 记录 |
| `site-bootstrap cert <domain>` | 单独调 certbot 签发/续期证书 |
| `site-bootstrap rollback` | 回滚到上一版部署（用远端快照） |
| `site-bootstrap doctor` | 检查本地工具链 + 远端连通性 + 配置完整性 |

全局标志 · Global flags：

- `--dry-run` — 只打印动作，不执行（适合第一次用时心里没底）
- `--verbose` — 打开 ssh / rsync 的 `-v`
- `--config <path>` — 用别的配置文件（默认 `site.yaml`）

---

## 配置 · site.yaml

最小可用：

```yaml
name: my-blog
domain: blog.example.com
server: my-vps   # 和 ~/.ssh/config 里的 Host 别名对应

deploy:
  type: static   # static 或 node
  source: dist   # 要上传的目录；"." 表示整个项目根
  # build: pnpm build   # 可选

ssl:
  provider: letsencrypt

dns:
  provider: cloudflare
  proxied: false   # true = 开 CF 代理（橙云），false = 仅 DNS（灰云）
```

更多示例见 [`examples/`](./examples)：纯静态、Next.js、纯反向代理三种常见场景。

---

## 设计原则 · Design principles

**一、能用 Bash 解决就不要装 Python/Node 环境。** 目标受众是"手上有 VPS 想快点上线"的开发者。进门门槛越低越好。

**二、远端状态只放两处。** 你的 `site.yaml` 是本地唯一事实，服务器上的 `/var/www/<domain>.prev` 是回滚快照。除此之外 site-bootstrap 不在你的机器或服务器上留任何状态、缓存、元数据。

**三、Cloudflare 凭据用 scoped API Token，不用 global key。** 最小权限是 `Zone:DNS:Edit` + 限定 Zone。这是比原始内部脚本更安全的实践。

**四、默认 `--dry-run` 友好。** 第一次用建议先 `site-bootstrap --dry-run deploy` 看一遍要跑哪些命令。

**五、出身血脉。** 这套工具的母版是一个真跑过多年生产的内部部署工具链，开源前经过了脱敏 + 重写 —— 把客户化的部分（特定域名、特定服务器别名、特定站型假设）全部参数化了。不是玩具项目。

---

## 适合 / 不适合 · Good / bad fits

**适合**：
- 你有 1 台或几台 Ubuntu / Debian VPS，跑 nginx
- 域名托管在 Cloudflare（或者不用 CF 也行，DNS 步骤会自动跳过）
- 站点是静态文件，或者是 `pm2 start` 能起来的 Node 应用
- 一个开发者 / 一家小工作室自己用

**不适合**：
- 大规模多环境（staging / canary / blue-green）—— 这套不做
- k8s / ECS / Cloud Run —— 用这些云原生工具链更合适
- 零停机滚动更新 —— 当前是"rsync 覆盖 + reload"，会有秒级空窗

---

## 系统要求 · Requirements

**本地**：`bash 4+`、`ssh`、`rsync`、`jq`、`curl`、`awk`。macOS / Linux 一般都齐。

**远端（VPS）**：`nginx`、`certbot`（SSL 时需要）、`pm2`（跑 Node 应用时需要）。Ubuntu 22.04 / Debian 12 是已测试环境。

**Cloudflare**（可选）：API Token 权限 `Zone:DNS:Edit`，限定你要动的 Zone。

---

## English quick reference

```bash
curl -fsSL https://raw.githubusercontent.com/tianmind-studio/site-bootstrap/main/install.sh | bash

site-bootstrap new my-blog
cd my-blog
cp .env.example .env   # add CF_API_TOKEN / CF_ZONE_ID

site-bootstrap --dry-run deploy   # preview
site-bootstrap deploy             # actually ship

site-bootstrap rollback           # undo the last deploy
```

`site.yaml` is the single source of truth. The CLI reads it, calls Cloudflare,
rsyncs your site to `/var/www/<domain>`, writes an nginx config, runs certbot,
and prints the verified URL. That's it.

See [`examples/`](./examples) for static / Node / pure-proxy configs, and
[`CHANGELOG.md`](./CHANGELOG.md) for what's in each release.

---

## Contributing

Bug reports, feature requests, PRs — all welcome via GitHub issues. Please
include:

- Your OS + `bash --version`
- The exact command you ran
- The output (with `--verbose`)

For non-trivial PRs, open an issue first so we can agree on the shape before
you write code.

---

## License

MIT © 2026 Tianmind Studio. See [LICENSE](./LICENSE).

<sub>Part of the <a href="https://github.com/491034170">Tianmind Studio</a> open-source toolchain for indie site operations.</sub>
