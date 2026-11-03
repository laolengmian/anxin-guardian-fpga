# 复现与 TD 工程准备

## 1. 无硬件 HDL 回归

安装 Python 3.10+ 和 Icarus Verilog，在仓库根目录执行：

```bash
python -I scripts/run_tests.py .
```

脚本依次运行数学、I²C/FIFO、CDC、13组原始波形、可配置系数、端到端和 Verilog-2005 编译测试。依赖 `iverilog`/`vvp` 的 PATH 查找，或环境变量 `IVERILOG`、`VVP`。不需要额外 pip 包。输出写入被 Git 忽略的 `results/` 和 `sim/vectors/`。

## 2. 完整 TD 源码视图：需要单独获取厂商文件

本仓库不分发13个厂商/板级参考文件。清单及匹配版本的 SHA256 位于 [vendor_dependencies.json](vendor_dependencies.json)。从你有权使用的完整源包获取这些文件，并保留其原目录布局；不要从本仓库寻找加密体或位流。

```bash
python -I scripts/import_vendor_ip.py . --source /path/to/licensed-complete-source
python -I scripts/prepare_project.py .
```

`/path/to/licensed-complete-source` 是你自己的授权源包根目录占位符，不是下载地址。导入器仅复制清单内13个文件，核验版本后放进 `.local_vendor/`，不修改许可，也不联网下载厂商 IP。文件版本不同会停止；应先核对接口和板级实现，不要盲目替换哈希来跳过版本检查。

工程准备脚本在 `build/td/` 生成工作副本与 `anxin_guardian_vitals.al`，在副本里重绑 include 和文件路径；**不修改跟踪中的 RTL，不启动 TD，不烧写**。打开生成的 `.al`，而不是直接打开 `td/project_template.al`。

本地原工程使用 Tang Dynasty 6.2.168116、EG4S20BG256。工程模板保留原文件属性和编译顺序，包括未启用的配套模块；不能据文件存在就将其列为已实现功能。

## 3. 传感器管脚

只有在核对 HX4S20C 扩展口、管脚占用和接口电压后，才将实际位置传入：

```text
python -I scripts/prepare_project.py . --scl-pin <confirmed-SCL-pin> --sda-pin <confirmed-SDA-pin>
```

尖括号内容是占位符，不可直接执行。脚本只检查语法和已有约束中的占用，不验证封装 IO 电压或板上线路。未指定位置时，工作副本明确记录 `sensor_pins_bound=false`。

## 4. 可见顶层展开检查

```bash
python -I scripts/check_top.py .
```

它分别记录严格展开和允许缺失模块的可见展开。外部依赖缺失时严格展开应报告缺少的厂商模块；只有可见部分返回成功并且缺失模块均来自已知依赖时，检查才通过。这个通过**不是**全系统功能仿真、TD综合、时序收敛或板测。

## 5. 公开范围

`.local_vendor/`、`build/`、`results/`、波形和编译产物都在 `.gitignore` 中。请勿 `git add -f` 厂商文件或私密材料。历史本机日志、原始ZIP、Word说明书和用户照片没有放入仓库。
