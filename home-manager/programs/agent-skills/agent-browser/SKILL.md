---
name: agent-browser
description: Connect to the persistent remote Chromium (`browser-agent-general` on vm-nix) over CDP. Use when a task needs Playwright CDP automation, an existing logged-in browser session, or noVNC manual login/CAPTCHA takeover.
---

# 通用远程浏览器

使用 `vm-nix` 上的持久化 Chromium 实例 `browser-agent-general`。

- CDP 地址：http://192.168.0.240:9422
- 人工接管界面：http://192.168.0.240:6082/vnc.html（需要 VNC 密码）
- 浏览器运行在 `vm-nix` 上，不要把本机 `localhost` 当作该浏览器地址。
- 访问上述局域网地址时绕过 HTTP/SOCKS 代理。

## 连接方式

使用前检查连通性：

```bash
curl --noproxy '*' --fail --connect-timeout 5 http://192.168.0.240:9422/json/version
```

通过项目环境中的 Playwright 连接已有浏览器（无需另行启动 Chromium）：

```python
browser = p.chromium.connect_over_cdp("http://192.168.0.240:9422")
```

- 复用已有登录状态时，使用 `browser.contexts[0]` 再调用 `context.new_page()`。
- `browser.new_context()` 会创建空白独立会话，不会继承已有登录。

## 共享使用规则

- 只操作和关闭自己创建的标签页；结束时断开客户端连接，保留浏览器与默认 context。
- 不关闭其他任务的页面、不清空登录状态、不重启容器；涉及共享登录态变更前先协调。
- 需要扫码登录或人工验证码时，让用户通过上述 noVNC 界面接管同一会话。
- 连接失败时直接报告错误，不自行修改防火墙或切换到其他浏览器实例。
