# s-ui-updater
s-ui 一键安装/更新/端口转发工具

## 一键安装
```bash
wget -N https://raw.githubusercontent.com/Wuzen28/s-ui-updater/main/s-ui-updater.sh && bash s-ui-updater.sh
```
## cf配置
### DNS设置
如果是绕cf：
1. 端口重写 (Origin Rules)​：如果 s-ui 监听 8080，则创建 Origin Rule：当主机名匹配时，重写目标端口为 8080
2. DNS：添加 A 记录指向 VPS，开启小黄云 (Proxied)​。
3. SSL/TLS 模式：设置为 Flexible（如果 s-ui 没开 TLS）或 Full（如果 s-ui 开了 TLS）。
