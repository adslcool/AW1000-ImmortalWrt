# QModem 本地补丁

AW1000 自己维护的 QModem 兼容补丁。

- `patch-sms-pdu.py`
  - 规范化 `+86`、空格、短横线等短信号码输入；
  - 对旧 QModem Next PDU 地址编码做语义锚点修补；
  - 上游若已重构，只输出 warning，不因补丁不匹配中断整机编译。

普通 Build 不从第三方地址下载这里的补丁。
