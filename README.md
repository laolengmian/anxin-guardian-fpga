# 安芯守护·声影融合终端

**把健康宣教、护理提醒与体征信息，汇聚到病房床旁的一块屏幕。**

安芯守护是一款基于 **国产FPGA** 的床旁多媒体信息融合终端。面向住院患者的健康宣教与床旁信息查看场景，将图片、配套语音、中文字幕、实体交互、分级提示和生命体征信息组织在同一套硬件系统中，通过 **HDMI_B统一输出画面与声音**。

**作品关键词：床旁护理终端 · 多媒体健康宣教 · 多源信息融合**

Anxin Guardian is an FPGA-based bedside audiovisual terminal integrating local educational media, physical interaction, status prompts and PPG-derived vital-sign information.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[应用背景](#为什么做这个作品) · [解决的问题](#要解决什么问题) · [系统方案](#怎样解决) · [作品亮点](#作品亮点) · [快速复现](#快速复现) · [接线与验证](#接线与验证)

## 为什么做这个作品

住院期间，饮食、休养、个人卫生和用药等内容需要反复讲解；患者查看宣教内容、听取提示和操作设备，也需要清晰、直接的入口。对于床旁终端，重点不只是“能显示图片”，还要让画面、旁白、字幕和操作反馈保持一致，让护理信息与设备状态在同一界面中易于辨认。

本作品选择以 **本地内容、实体按键和独立运行** 为基础：宣教素材保存在TF卡，常用操作通过六键完成，声音与图像统一输出。FPGA承担文件读取、存储调度、音视频处理、界面合成和采集解算，终端日常运行不依赖额外的PC、手机或云端业务客户端。电脑用于开发、素材准备和调试，不是患者侧运行终端。

这是面向床旁护理宣教场景的工程原型；作品不将医院部署、临床诊断或减少护理工作量的量化效果列为已取得成果。

## 要解决什么问题

| 设计问题 | 作品中的解决方式 |
| --- | --- |
| 图片、语音和字幕各自运行，容易出现换图后旁白或字幕仍属于上一页 | 使用统一页面身份关联BMP、WAV与字幕；字幕跟随实际消费的PCM样本推进 |
| 只按固定秒数翻页，较长旁白可能被截断 | 自动轮播同时检查页面可见时长、旁白消费结束和尾部等待；手动操作优先 |
| TF读取、图像装载与连续视频输出节奏不同 | 四幅RGB565画布驻留SDRAM，以Bank有效性、FIFO背压和地址映射组织显示与转场 |
| 宣教、参数、提示和控制反馈容易分散成多个独立界面 | 按图层和优先级在同一画面呈现护理信息、字幕、OSD、音频包络与生命体征结果 |
| 异常输入、无效读数和业务提醒容易混在一起 | 分别管理媒体错误、参数有效位与Warning/Emergency业务输入，配合安全静音和有界恢复 |

## 怎样解决

### 三类输入，一套融合终端

| 输入来源 | FPGA内部处理 | 床旁呈现 |
| --- | --- | --- |
| TF卡的图片与语音 | SPI/FAT32读取、BMP解码与缩放、四Bank缓存、WAV/PCM播放 | 健康饮食、安心休养、个人卫生、安全用药四组主题及配套语音 |
| 六键与提示拨码 | 去抖、请求仲裁、参数调节、帧/样本边界提交 | 亮度、音量、手动切页、自动轮播、OSD和分级提醒 |
| MAX30102红光/红外样本 | I²C/FIFO采集、定点滤波、心率/血氧/呼吸率估计、有效性管理 | 同屏显示三项参数及有效状态 |

```text
TF卡 ─→ SPI / FAT32 ─→ BMP解码 / 缩放 ─→ 四Bank SDRAM ─→ 图层合成 ─→ HDMI_B画面
                  └─→ WAV / PCM ─→ 字幕计数 / 提示混合 / 音量 / SAFE ─→ HDMI音频
                                                            └─→ Audio Monitor
六键 / 拨码 ─→ 去抖 / 请求仲裁 / 页面与参数控制 ───────────────────→ 图层与声音
MAX30102 ─→ I²C / FIFO ─→ 定点PPG算法 ─→ 65位原子跨域快照 ─────────→ 参数显示
```

### 硬件平台

| 项目 | 配置 |
| --- | --- |
| 主控 | HX4S20C开发板 / Anlogic EG4S20BG256 |
| 本地存储 | FAT32 TF卡，只读SPI文件服务 |
| 图像缓存 | 封装内8 MiB SDRAM；四幅画布共7,372,800字节 |
| 显示 | 1280×720有效画面，HDMI_B输出图像与声音 |
| 音频 | 48 kHz、16位、小端、单声道PCM WAV |
| 实体控制 | 六键：亮度±、音量±、自动轮播、下一主题 |
| 采样模块 | MAX30102，100 Hz红光/红外双通道 |

## 作品亮点

### 1. 页面身份贯穿声、画、字与操作

四个主题不是各放一张图、再独立播放一段声音。系统以页面身份关联图片Bank、旁白和字幕，每页三段字幕，共十二段；字幕时间依据 **真正被消费的PCM样本**，不把文件读完误认为声音播完。自动轮播默认关闭，开启后同时满足最少8秒可见停留、旁白结束和约0.5秒尾等待，手动切换优先。

### 2. 四Bank驻留缓存与地址级擦除转场

四幅完整画布提前驻留SDRAM，只有装载完成且有效的Bank才参与显示。切换主题时，通过读地址映射选择新旧Bank，自上而下推进擦除边界，默认每完成一次完整读取会话推进24行。它复用存储读取链路，不需要临时生成一张过渡图片，也不依赖在TF卡上重新拼接画面。

### 3. 多源信息在一个界面有序融合

护理主题作为主画面，床位信息、护理计划、中文字幕、亮度/音量OSD、数字音频包络和体征卡片按坐标与优先级叠加。页面、OSD与相关字段在帧边界锁存，音量和提示混合在样本边界处理；多字段参数以 **65位原子快照** 跨域提交，避免同一帧出现新旧结果混组。

### 4. 从原始PPG到三项参数的硬件解算

FPGA通过I²C初始化MAX30102并读取FIFO中的18位Red/IR原始样本，再完成定点滤波、周期检测、窗口统计、整数平方根和除法。结果不是从一组目标数值直接送到显示端；每项参数都保留独立有效位，无接触、断流、饱和或信号不足时撤销相应读数。

### 5. 声音输出可观察，异常状态可区分

Audio Monitor取样点位于最终音量处理与SAFE门之后，以每240个有效样本统计的最小值、最大值和峰值形成数字音频包络，连接“正在播放什么、调到哪一档、最终输出如何”三件事。媒体格式校验、Bank有效性、跨域握手和最多三次有界恢复维护运行边界；外部业务提醒和媒体故障分别呈现。

## 生命体征链路

MAX30102配置为7位地址 `0x57`，100 Hz、411 μs/18位、Red/IR双通道，每组六字节；ADC范围4096 nA，默认LED电流寄存器 `0x24`。

| 参数 | 处理机制 | 窗口或范围 |
| --- | --- | --- |
| 心率 | 两级去基线、低通、自适应包络阈值、迟滞脉搏检测与四周期平均 | `HR = floor(60 Fs × 4 / ΣP)`；周期门限对应35–220次/min |
| 血氧估计 | 两路AC RMS与DC均值，串行平方根/除法，双波长比值换算 | 1024点，即10.24秒；`R = ACred × DCir / (ACir × DCred)`；`SpO₂ = A − B R` |
| 呼吸率 | IR低频基线调制、漂移抑制、两级低通、迟滞与四周期估计 | 6–40次/min；为PPG推导呼吸率 |

100 Hz是采样率，不表示每10 ms就得到三项完整新结果。`A=110`、`B=25`是可配置默认系数，具体光学结构和使用条件下的精度需实测标定；PPG呼吸率也不等于独立胸带或气流传感器读数。

生产链路在 `rtl/`，由顶层 `top_4bank_720p_m9_final_candidate` 的 `u_vital_processing` 接入终端。`sim/`和 `scripts/test_algorithm.py` 是独立测试环境，不参与上板后的传感器输入或业务运行。

## 接线与验证

### 传感器管脚已绑定

依据《HX4S20开发板手册-HDL版2410》第7页图2-4及J2扩展口表：

| MAX30102信号 | 扩展口接点 | FPGA球号 |
| --- | --- | --- |
| SCL | **J2第31脚 / GPIOB_26** | **J12** |
| SDA | **J2第32脚 / GPIOB_27** | **K11** |
| GND | J2第30脚或第12脚 | GND |
| 3.3 V电源参考 | J2第29脚 | 按模块规格核对供电 |

扩展IO为3.3 V；SCL/SDA为开漏，内部弱上拉关闭，需要合适的外部上拉与共地。模块供电和信号兼容性按实际转接板核对，不将5 V直接接入FPGA信号。孔序按实物1脚和缺口定位，**J12/K11不是排针第12/11孔**。完整说明见 [硬件接入](docs/HARDWARE.md)。

### 验证进度

| 项目 | 状态 | 记录 |
| --- | --- | --- |
| 采集与算法HDL回归 | 七组套件通过 | [TEST_REPORT.json](docs/validation/TEST_REPORT.json) |
| 原始PPG波形验证 | 13组工况通过，每组90秒等效采样 | [algorithm_results.json](docs/validation/algorithm_results.json) |
| I²C→算法→跨域→显示 | 45秒等效链路通过；包含断开后有效位撤销 | [验证说明](docs/validation/README.md) |
| 生命体征采集与显示上板功能 | **实测通过** | [BOARD_TEST_RECORD.json](docs/validation/BOARD_TEST_RECORD.json) |
| 传感器接点映射 | 手册核对完成 | [PIN_ASSIGNMENT_REFERENCE.json](docs/PIN_ASSIGNMENT_REFERENCE.json) |

统一状态见 [VERIFICATION_SUMMARY.json](docs/validation/VERIFICATION_SUMMARY.json)。功能实测、HDL回归和测量精度分别记录，不用一个“通过”替代所有测试项目。公开包不附位流、独立仪器采样或量化临床精度数据。

## 快速复现

### 无硬件运行采集与算法验证

需要Python **3.10+**、Icarus Verilog（`iverilog`、`vvp`）；Python脚本仅用标准库。

```bash
git clone https://github.com/laolengmian/anxin-guardian-fpga.git
cd anxin-guardian-fpga
python -I scripts/test_project_tools.py .
python -I scripts/run_tests.py .
```

Windows可用 `py -3` 替代 `python`。将Icarus加入PATH，或通过环境变量 `IVERILOG`、`VVP` 指定工具位置。结果写入忽略的 `results/`，确定性激励写入 `sim/vectors/`；以本次 `results/TEST_REPORT.json` 为准。

### 准备完整TD工作副本

本仓库公开自研逻辑、测试平台和复现脚本，**不分发13个受限的安路/板级依赖，也不包含TF图片音频、照片、手册PDF或位流**。从合法取得的完整工程导入匹配依赖后：

```bash
python -I scripts/import_vendor_ip.py . --source /path/to/licensed-complete-source
python -I scripts/prepare_project.py .
```

打开生成的 `build/td/anxin_guardian_vitals.al`。默认使用已核对的J12/K11；本地改线配置保存在忽略的工作副本中，重复准备会保留。明确取消绑定用 `--unbound`。准备脚本不修改跟踪RTL、不运行TD、不烧写硬件。详见 [BUILD.md](docs/BUILD.md)。

## 源码导航

| 路径 | 内容 |
| --- | --- |
| `rtl/` | MAX30102采集、I²C主机、PPG解算、整数运算、原子快照 |
| `inputs/candidate/rtl/` | 顶层、页面控制、中文界面与体征覆盖层 |
| `inputs/frozen/rtl/` | 配套媒体、音频、视频、跨域与可靠性模块 |
| `inputs/constraints/` | 基础IO约束、已绑定的体征IO约束与时序约束 |
| `sim/` | 数学、协议、原始波形、CDC与端到端测试平台 |
| `scripts/` | HDL回归、工程准备、依赖导入和工具测试 |
| `td/project_template.al` | 115条相对路径记录的TD工程模板 |
| `docs/validation/` | 发布验证摘要、波形结果及实板功能记录 |

- [硬件与接线](docs/HARDWARE.md)
- [TF媒体格式与准备](docs/MEDIA.md)
- [复现与TD工程](docs/BUILD.md)
- [算法模块分工](docs/ALGORITHM.md)
- [第三方组件与开源边界](THIRD_PARTY_NOTICES.md)

## 使用范围与许可

Warning/Emergency由外部开关触发，不是心率或血氧算法自动判断病情。Audio Monitor展示数字音频幅度，不是ECG或扬声器声压。视频配置为75 MHz像素时钟、1650×750总时序，约60.606 Hz，不写成精确标准74.25 MHz的720p60。

自研代码与文档采用 [MIT License](LICENSE)；字体/字形按 [SIL OFL 1.1](LICENSES/Adobe-OFL-1.1.txt) 分发。未发布的厂商组件遵循原许可。完整说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

欢迎通过Issues反馈复现问题。请附工具版本、步骤和必要日志，不提交密码、Token、个人照片或未获授权的厂商文件。
