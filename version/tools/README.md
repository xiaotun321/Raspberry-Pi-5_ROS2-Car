# 构建辅助工具

| 文件 | 用途 |
| --- | --- |
| `verify_binary.py` | 打包时校验 ELF 架构及内嵌版本 |
| `make_ver_header.py` | 生成或验证 .bivi 头部 |
| `relativize_sysroot.py` | 将复制来的 sysroot 绝对链接改为相对链接 |

前两个工具由 `vergen.sh` 调用。同步新的 sysroot 后执行：

```bash
python3 version/tools/relativize_sysroot.py "$HOME/rpi5-sysroot"
```
