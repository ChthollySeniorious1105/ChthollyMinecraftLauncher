# AI 变声模型（client/native/models → 安装后位于 ai\models）

| 文件 | 作用 | 来源 | 许可 | SHA256 |
|---|---|---|---|---|
| `hubert_base_l12.onnx` | HuBERT-base 第 12 层内容特征，输入固定 `source [1,32000]`（16 kHz 2 秒）→ `features [1,99,768]` | hf-mirror `ohnoitsaninja/rvc-base-onnx` `onnx/hubert_base_layer12_nomask_32000.onnx`（原始权重来自 lj1995/VoiceConversionWebUI `hubert_base.pt`） | MIT | 60bd2041afb96b668f3d602b42e2781afc9e2ee5cb51c1247bb12491e4c8c547 |
| `rmvpe.onnx` | RMVPE 音高检测：`input [1,128,T]`（log-mel，T 为 32 的倍数）→ `output [1,T,360]`（20 cent 一格的显著性） | 同上 `assets/rmvpe.onnx` | MIT | 5370e71ac80af8b4b7c793d27efd51fd8bf962de3a7ede0766dac0befa3660fd |
| `rvc_base_40k.onnx` | RVC v2 生成器（声码器），内置“基础音色”，109 个说话人 | 由 `tools/model_export/export_rvc_base.py` 从 lj1995/VoiceConversionWebUI `pretrained_v2/f0G40k.pth` 导出 | MIT | c42bfdc951858818d65f779139506f637194bfdc5ca480fec5a954be81fe1401 |

生成器 I/O：`feats f32 [1,T,768]`、`p_len i64 [1]`、`pitch i64 [1,T]`（1–255 粗音高）、`pitchf f32 [1,T]`（Hz）、`sid i64 [1]`、`rnd f32 [1,192,T]` → `audio f32 [1,1,T*400]`（40 kHz，每帧 10 ms）。
metadata_props `metadata` 为 JSON：`{"samplingRate":40000,"f0":true,"embChannels":768,"speakers":109,...}`。

用户自定义音色：把任何 **RVC v2、768 维、带 f0** 的 ONNX 模型（例如 w-okada VCClient 导出的 `*_simple.onnx`，fp16/fp32 均可，`rnd` 输入可有可无）放进安装目录的 `ai\voices\`。
请只使用有权使用的声音；不要用别人的声音冒充他人。

> 下载源：huggingface.co 在本机网络不可达，全部通过 https://hf-mirror.com 获取；如需重新下载，可让用户手动下载后放到这里（见 ARCHITECTURE.md §6.4）。
