# s-ui-updater
s-ui 一键安装/更新/端口转发工具

## 一键安装
```bash
wget -N https://raw.githubusercontent.com/Wuzen28/s-ui-updater/main/s-ui-updater.sh && bash s-ui-updater.sh
```
# s-ui 节点与 Cloudflare 配置指南

本脚本支持多种协议共存部署。为了确保连接成功，请根据你使用的协议类型参考以下配置说明。

---

### 方案一：WS + Cloudflare (抗封锁/CDN加速)
*适用于 IP 被墙或需要隐藏真实 IP 的场景。*

1. **DNS 管理**：在 Cloudflare 添加 A 记录指向 VPS IP，**必须开启小黄云 (Proxied)**。
2. **端口重写 (Origin Rules)**：创建规则，当主机名匹配时，设置 `Destination Port` 重写为 `8080`（或你在 s-ui 中设置的端口）。
3. **SSL/TLS 模式**：
   - 若 s-ui 节点 **未开启** TLS：设置为 `Flexible`。
   - 若 s-ui 节点 **已开启** TLS：设置为 `Full` 或 `Full (Strict)`。
4. **技术要点**：
   - 在 CF 的 `Network` 菜单中，确保 **WebSockets** 开关已开启。
   - 客户端“端口”填 `443`，“TLS”开启。

---

### 方案二：VLESS + REALITY (极致速度/高隐蔽性直连)
*适用于追求低延迟、高带宽，且 VPS 端口未被封锁的场景。*

1. **DNS 管理**：在 Cloudflare 添加 A 记录指向 VPS IP，**必须关闭小黄云 (DNS Only)**。
2. **s-ui 设置**：
   - **端口**：建议使用 `443`。
   - **Dest/SNI**：必须填入国外大厂域名（如 `www.microsoft.com`），不可填入你自己的域名。
3. **技术要点**：
   - **严禁开启小黄云**，否则会导致伪装失效。
   - 流量直连 VPS，不经过 Cloudflare 节点。

---

### 方案三：Hysteria2 (UDP 暴力加速/多端口跳跃)
*适用于网络环境恶劣、运营商 QoS 严重的场景。*

1. **服务端设置**：
   - **TLS 配置**：必须在 s-ui 中开启 TLS，并配置该域名的有效证书。
   - **脚本转发**：使用 `s-ui-updater` 菜单，将外部 UDP 端口段（如 `20000:20010`）转发到内部监听端口（如 `443`）。
2. **DNS 管理**：在 Cloudflare 添加 A 记录指向 VPS IP，**必须关闭小黄云 (DNS Only)**。
3. **技术要点**：
   - **UDP 限制**：CF 免费版不支持 UDP 代理，开启小黄云会导致 Hysteria2 无法连接。
   - **端口跳跃**：客户端“端口”建议填写端口段（如 `20000-20010`），可绕过运营商限速。

---

### 核心要点总结

- **协议共存**：在同一 VPS 上，Reality (TCP:443) 与 Hysteria2 (UDP:443) 可以共存，因为协议类型不同。
- **Origin Rules 优势**：使用端口重写后，客户端统一用 `443` 连接，服务端用 `8080`，隐蔽性更高。
- **脚本快捷调用**：
  ```bash
  # 安装或调出菜单
  s-ui-updater

### 进阶技巧：流媒体与 AI 解锁 (Gemini/Netflix)

如果你的 VPS 线路较差导致无法使用 Gemini 或 Netflix，建议配合 **Cloudflare WARP** 进行分流解锁：

1. **安装 WARP**：在 VPS 执行 `bash <(curl -fsSL https://raw.githubusercontent.com/P3TERX/warp.sh/main/warp.sh) proxy` 开启本地 1080 端口代理。
2. **s-ui 分流设置**：
   - **Outbound (出站)**：添加一个 Socks5 协议，指向 `127.0.0.1:1080`，标签设为 `WARP`。
   - **Routing (路由)**：添加规则，将 `geosite:netflix`、`google.com` (Gemini) 等域名的出站指向 `WARP` 标签。
3. **效果**：普通流量直连保证速度，解锁流量走 WARP 绕过检测。

