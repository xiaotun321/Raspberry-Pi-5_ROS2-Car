# 离线回归测试

纯离线测试：不写 `/work`，不启动真实服务，也不执行目标架构的程序。
构建时由 CTest 收录（`version_archive`、`binary_metadata`），也可单独运行。

## 用途

| 脚本 | 覆盖内容 |
| --- | --- |
| `test_update.py` | 归档路径安全、校验和、版本清单、带头版本包的剥离，以及版本目录切换与回退 |
| `test_binary.py` | 打包检查：架构不符、版本不符、缺字段等错误分支 |

## 用法

```bash
python3 -m pytest version/test -q
```

两个脚本都用 `importlib` 直接加载被测模块（`../update.py`、
`../tools/verify_binary.py`），因此测试与被测代码保持同一份实现。
