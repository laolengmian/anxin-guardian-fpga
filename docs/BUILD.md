# 复现与TD工程准备

## 1. 纯软件运行工具测试与HDL回归

安装Python 3.10+、Icarus Verilog，将 `iverilog` 和 `vvp` 加入PATH，或设置环境变量 `IVERILOG`、`VVP`：

```bash
python -I scripts/test_project_tools.py .
python -I scripts/test_publication.py .
python -I scripts/run_tests.py .
```

工具测试使用Python标准库；HDL回归依次覆盖数学、I²C/FIFO、CDC、13组原始PPG波形、可配置血氧系数、端到端和Verilog-2005编译。不需要开发板、厂商IP或额外pip包。

结果写到忽略的 `results/` 和 `sim/vectors/`。测试开始即将 `results/TEST_REPORT.json` 标为运行中，只有全部完成才写入通过；失败或中断不使用历史通过状态代替。

## 2. 补齐合法取得的厂商依赖

13个安路/板级参考文件未在公共源码中再分发，版本及SHA256见 [vendor_dependencies.json](vendor_dependencies.json)。从合法持有的完整工程中导入：

```bash
python -I scripts/import_vendor_ip.py . --source /path/to/licensed-complete-source
```

`/path/to/licensed-complete-source` 是本地完整工程根目录占位符，不是下载地址。该目录下应有 `inputs/`，而不是把RAR路径直接作为参数。

导入器先核验全部清单成员，成功后才写入忽略的 `.local_vendor/`。不联网下载、不导入额外文件，不改变原许可。三份引用 `global_def.v` 的依赖支持已锁定的include目录迁移哈希；只允许这一目录字符串变化，其他字节，包括加密体和换行，仍必须匹配。算法或IP版本不同不能靠修改哈希绕过检查。

## 3. 生成完整TD工作副本

```bash
python -I scripts/prepare_project.py .
```

生成 `build/td/anxin_guardian_vitals.al`，打开这一文件，不直接打开模板。脚本会复制公开源码与本地依赖，在工作副本重绑include和115个工程记录；**不修改跟踪RTL、不运行综合、布局布线、Bitgen或硬件下载**。

依赖不齐会明确返回非零状态，不生成虚构厂商模块。工程目标为EG4S20BG256，原TD环境为Tang Dynasty 6.2.168116。其他版本需支持该器件和所用IP。完整源码层次还包含未接入顶层的配套模块，文件存在不表示功能已启用。

## 4. 默认管脚、局部改线与取消绑定

默认配置在 `docs/SENSOR_PIN_CONFIG.json`：

- SCL：J2第31脚 / GPIOB_26 / FPGA J12。
- SDA：J2第32脚 / GPIOB_27 / FPGA K11。
- 手册依据与电气要求见 [HARDWARE.md](HARDWARE.md)。

第一次准备读取仓库默认值；以后优先读取忽略的 `build/td/SENSOR_PIN_CONFIG.json`，保留本地选择。明确覆盖或取消：

```bash
# 明确恢复本项目已核对的接线
python -I scripts/prepare_project.py . --scl-pin J12 --sda-pin K11

# 取消本地工作副本的传感器位置绑定
python -I scripts/prepare_project.py . --unbound
```

自定义管脚须同时给出SCL/SDA。脚本检查语法、重复和基础约束占用；不能代替新管脚的板上布线及电压核查。换成其他接线后，`PROJECT_BINDING.json` 的实测归档匹配状态变为待测，不继承原配对结果。取消绑定是显式操作，默认重跑不会自动清空配置。

## 5. 可见顶层展开

```bash
python -I scripts/check_top.py .
```

严格展开记录缺失模块，可见展开仅允许依赖清单中的黑盒；未知缺失类型使检查失败。可见展开通过不是全系统功能仿真或器件时序收敛。运行不会烧写开发板。

## 6. 实际上板

生命体征采集与显示链路已实测通过，记录见 [BOARD_TEST_RECORD.json](validation/BOARD_TEST_RECORD.json)。复现者仍需按自己的模块和板卡确认供电、共地、上拉、接点；完成当前代码的综合、布局布线、时序检查和Bitgen后下载本次位流。公共仓库没有预编译位流，TD准备成功也不表示已经生成或下载固件。

## 7. 公开边界

`.local_vendor/`、`build/`、`results/`、波形和编译产物均被忽略。不要强制添加厂商依赖、私密材料或凭据。TF图片音频、照片、Word/PDF报告、原始ZIP与板卡手册PDF未发布；媒体格式见 [MEDIA.md](MEDIA.md)。
