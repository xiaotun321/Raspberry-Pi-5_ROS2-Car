# 构建机工具

只��构建机上运行，不随版本包安装到开发板。由 `version/vergen.sh`、
`version/build_sysroot.sh` 调用。

## 用途

| 脚本 | 作用 |
| --- | --- |
| `verify_binary.py` | 打包前核对二进制的架构与嵌入版本，防止把 x86 程序或旧版本装进 ARM 包 |
| `make_ver_header.py` | 给版本包加 1024 字节头部（magic、版本、构建时间、长度、CRC32），或校验已有包的头部 |
| `relativize_sysroot.py` | 把 sysroot 副本里的绝对符号链接改成相对链接，防止误指向主机库 |

## 用法

```bash
# 校验二进制（vergen.sh 内部调用）
python3 version/tools/verify_binary.py <可执行文件> <arm64|amd64> <版本号> <提交号>

# 给版本包加头，或校验已有包的头部
python3 version/tools/make_ver_header.py DEAD5409 1.0.0 <输入.bin> <输出.bivi>
python3 version/tools/make_ver_header.py --verify <版本包>

# 处理 sysroot 副本里的符号链接（build_sysroot.sh 内部调用）
python3 version/tools/relativize_sysroot.py <sysroot 目录>
```

头部格式与产线工具 `tools_ver_maker` 一致，`update.py` 依赖 `ver_header.py`
解析同一个格式。
