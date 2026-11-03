# 安芯守护·声影融合终端

**Anxin Guardian — an FPGA bedside audiovisual information terminal.**

基于国产 **Anlogic EG4S20BG256 / HX4S20C** 开发板的床旁多媒体终端，将本地护理主题图片、语音、中文字幕、六键交互、分级提示与 MAX30102 原始信号处理组织在一套 Verilog 硬件链路中。

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> 本仓库公开自研逻辑、测试平台和复现脚本。**不包含受限的安路/板级参考 IP，也不包含 TF 媒体素材或位流。** 七组采集算法 HDL 回归无需这些 IP 即可运行；完整 TD 工程必须先合法取得并在本地补齐依赖。字体位图保留 OFL 许可，不纳入 MIT。

## 主要功能

- **多媒体显示**：只读 SPI/FAT32、24 位 BMP 校验与指定比例缩放、RGB565 四 Bank 驻留画布、1280×720 有效画面、地址映射自上而下擦除转场。
- **音画与字幕**：48 kHz / 16 位 / 单声道 WAV，四个主题、每页三段中文字幕；字幕与轮播依据实际 PCM 消费计数推进。
- **实体交互**：六键控制亮度、音量、自动轮播和下一主题；0–8 档参数及屏幕 OSD，手动切页优先。
- **声音可视化与可靠性**：最终音量/安全门之后的 PCM 包络、媒体格式与 Bank 有效性检查、FIFO 背压、复位分域和最多三次有界媒体恢复。
- **业务提示**：外部拨码触发 Warning / Emergency，Emergency 优先，配合背景和提示音处理；不是算法自动判定病情。
- **生命体征处理**：MAX30102 双通道采集，FPGA 内定点计算心率、血氧估计和 PPG 推导呼吸率，65 位原子快照跨域并按帧提交。

本项目没有独立 PC / 手机 / 云端业务客户端。

## 系统数据流

```text
TF 卡 → SPI / FAT32 → BMP / 缩放 → 四 Bank SDRAM → 视频图层 → HDMI_B
                 └→ WAV / PCM → 字幕计数 / 提示混合 / 音量 / SAFE → HDMI 音频
                                                       └→ Audio Monitor
六键 / 拨码 → 去抖 / 仲裁 / 页面与参数控制 ─────────────→ 图层与声音
MAX30102 → I²C / FIFO → 定点 PPG 算法 → 65 位快照 ────→ 参数显示
```

Audio Monitor 展示数字音频幅度，不是 ECG，也不是扬声器声压测量。

## 快速运行：不需要 FPGA 板或厂商 IP

需要 Python **3.10+** 与 **Icarus Verilog**（`iverilog`、`vvp`）。Python 脚本仅使用标准库。

```bash
git clone https://github.com/laolengmian/anxin-guardian-fpga.git
cd anxin-guardian-fpga
python -I scripts/run_tests.py .
```

Windows 可使用 `py -3` 替代 `python`。将 Icarus 加入 PATH；也可设置环境变量 `IVERILOG`、`VVP` 为两个可执行文件的位置。无需联网调用模型或外部数据。

测试在 `results/` 生成 JSON、CSV、日志和局部 VCD；确定性原始 Red/IR 激励写入 `sim/vectors/`。这些生成文件默认不提交到 Git。**结果以当次生成的 `results/TEST_REPORT.json` 为准**，失败或中断不能用历史结果代替。

已归档的发布前复测摘要见 [docs/validation](docs/validation/README.md)。完整回归可在安装 Icarus 的 Windows/Linux 环境执行；本次发布不包含需要额外 GitHub workflow 权限的自动CI配置。

## 三支路算法

传感器配置：7 位地址 `0x57`，100 Hz，Red/IR 各 18 位，每组六字节；411 μs 脉宽、4096 nA ADC 范围，LED 电流寄存器默认 `0x24`。

| 参数 | 处理路径 | 窗口与约束 |
| --- | --- | --- |
| 心率 | 两级去基线、低通、自适应包络、迟滞越阈、四周期平均 | `HR = floor(60 Fs × 4 / ΣP)`；35–220 次/min 周期门限 |
| 血氧估计 | 两通道 AC RMS / DC 均值、串行平方根与除法、比值换算 | 1024 点，即 10.24 秒；`R = ACred × DCir / (ACir × DCred)`；`SpO₂ = A − B R` |
| 呼吸率 | IR 低频基线调制、慢漂移抑制、两级低通、迟滞与四周期 | 6–40 次/min；是 PPG 推导结果，不是独立呼吸传感器读数 |

`A=110`、`B=25` 为可配置默认系数，不能替代具体模块/光学条件的实测标定。无接触、断流、饱和和信号不足会撤销有效位。100 Hz 是采样率，**不表示每 10 ms 都得到三项完整新估计**。滤波系数与周期门限按当前采样率设计。

## 工程入口

| 路径 | 内容 |
| --- | --- |
| `rtl/` | I²C、MAX3010x FIFO、定点算法、除法/平方根、原子快照与采集子系统 |
| `inputs/candidate/rtl/` | 顶层、页面控制、界面和参数覆盖层 |
| `inputs/frozen/rtl/` | 配套媒体、音频、视频、跨域及可靠性逻辑；不代表每个模块都在当前顶层启用 |
| `sim/` | 数学、协议、算法、跨域和端到端测试平台 |
| `scripts/` | 回归、TD 工作副本准备和本地依赖导入 |
| `td/project_template.al` | 无本机绝对路径的 TD 工程模板 |
| `docs/` | 接入、媒体契约、验证边界和第三方依赖清单 |

顶层模块为 `top_4bank_720p_m9_final_candidate`，文件为 `inputs/candidate/rtl/top_4bank_720p_m9_vitals.v`。

- [完整 TD 工程的本地准备](docs/BUILD.md)
- [硬件接口与传感器接入](docs/HARDWARE.md)
- [TF 媒体格式](docs/MEDIA.md)
- [第三方许可与公开范围](THIRD_PARTY_NOTICES.md)

## 验证状态与适用范围

采集/算法七组 HDL 回归包含 13 组、每组 90 秒等效原始 PPG 输入，另有 45 秒等效 I²C→算法→跨域→参数显示测试。它们证明给定输入和接口条件下的 RTL 行为，**不等同于人体测量准确度或当前算法版板级验收**。

当前新增传感器 SCL/SDA 尚需按实际扩展口绑定；TD 综合、布局布线、Bitgen、实采与标定需在本地完成。本仓库不附新位流，不提供临床诊断功能。像素时钟配置 75 MHz、总时序 1650×750，换算约 60.606 Hz，不将其称为精确标准 74.25 MHz 720p60。

## 开源许可

自研代码和文档采用 [MIT License](LICENSE)。字体/字形部分按 [SIL OFL 1.1](LICENSES/Adobe-OFL-1.1.txt) 分发；未随仓库发布的安路和板级参考 IP 仍受其原许可约束。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

欢迎通过 Issues / Pull Requests 反馈复现问题。请勿提交密码、Token、个人照片或未获再分发授权的厂商文件。
