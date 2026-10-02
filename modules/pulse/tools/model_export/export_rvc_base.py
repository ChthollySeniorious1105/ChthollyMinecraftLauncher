"""Export the MIT-licensed RVC v2 pretrained generator (lj1995/VoiceConversionWebUI
pretrained_v2/f0G40k.pth) to an ONNX graph usable by Pulse's voice changer.

The infer_pack code on the HF repo is the v1 (256-dim) variant; v2 differs only in
 - TextEncoder input dim 768 (HuBERT layer 12)
 - emb_g is nn.Embedding(109, 256)
 - the NSF decoder is conditioned on the speaker embedding (dec.cond)
so those parts are re-declared here. SineGen is rewritten ONNX-friendly.
"""
import json, math, sys
import numpy as np
import torch
from torch import nn
from torch.nn import functional as F

sys.path.insert(0, '.')
from infer_pack import attentions, commons, modules
from infer_pack.models import ResidualCouplingBlock, GeneratorNSF

SR = 40000
UPP = 400  # 10*10*2*2 samples per feature frame (100 fps)


class TextEncoder768(nn.Module):
    def __init__(self, out_ch, hidden, filt, heads, layers, ks, p):
        super().__init__()
        self.out_channels, self.hidden_channels = out_ch, hidden
        self.emb_phone = nn.Linear(768, hidden)
        self.lrelu = nn.LeakyReLU(0.1, inplace=True)
        self.emb_pitch = nn.Embedding(256, hidden)
        self.encoder = attentions.Encoder(hidden, filt, heads, layers, ks, p)
        self.proj = nn.Conv1d(hidden, out_ch * 2, 1)

    def forward(self, phone, pitch, lengths):
        x = self.emb_phone(phone) + self.emb_pitch(pitch)
        x = self.lrelu(x * math.sqrt(self.hidden_channels)).transpose(1, -1)
        x_mask = torch.unsqueeze(commons.sequence_mask(lengths, x.size(2)), 1).to(x.dtype)
        x = self.encoder(x * x_mask, x_mask)
        stats = self.proj(x) * x_mask
        m, logs = torch.split(stats, self.out_channels, dim=1)
        return m, logs, x_mask


class SineSource(nn.Module):
    """ONNX friendly harmonic source (harmonic_num=0) matching SourceModuleHnNSF."""
    def __init__(self):
        super().__init__()
        self.l_linear = nn.Linear(1, 1)
        self.sine_amp, self.noise_std = 0.1, 0.003

    def forward(self, f0, upp):
        f0u = f0.unsqueeze(1).repeat_interleave(upp, dim=2)  # [B,1,T*upp] nearest upsampling
        rad = f0u / SR
        phase = torch.cumsum(rad, dim=2)
        phase = phase - torch.floor(phase)
        sine = torch.sin(phase * (2 * math.pi)) * self.sine_amp
        uv = (f0u > 0).to(sine.dtype)
        amp = uv * self.noise_std + (1 - uv) * (self.sine_amp / 3)
        sine = sine * uv + amp * torch.randn_like(sine)
        return torch.tanh(self.l_linear(sine.transpose(1, 2))), None, None


class PulseRVC(nn.Module):
    def __init__(self):
        super().__init__()
        inter, hidden = 192, 192
        self.enc_p = TextEncoder768(inter, hidden, 768, 2, 6, 3, 0)
        self.dec = GeneratorNSF(inter, '1', [3, 7, 11], [[1, 3, 5]] * 3, [10, 10, 2, 2], 512,
                                [16, 16, 4, 4], gin_channels=256, sr=SR, is_half=False)
        self.dec.m_source = SineSource()
        self.flow = ResidualCouplingBlock(inter, hidden, 5, 1, 3, gin_channels=256)
        self.emb_g = nn.Embedding(109, 256)

    def forward(self, feats, p_len, pitch, pitchf, sid, rnd):
        g = self.emb_g(sid).unsqueeze(-1)
        m_p, logs_p, x_mask = self.enc_p(feats, pitch, p_len)
        z_p = (m_p + torch.exp(logs_p) * rnd * 0.66666) * x_mask
        z = self.flow(z_p, x_mask, g=g, reverse=True)
        return self.dec(z * x_mask, pitchf, g=g)


def main():
    ckpt = torch.load('f0G40k.pth', map_location='cpu', weights_only=False)['model']
    ckpt = {k: v.float() for k, v in ckpt.items() if not k.startswith('enc_q')}
    net = PulseRVC()
    missing, unexpected = net.load_state_dict(ckpt, strict=False)
    print('missing', missing)
    print('unexpected', unexpected)
    net.dec.remove_weight_norm()
    for i in range(net.flow.n_flows):
        net.flow.flows[i * 2].remove_weight_norm()
    net.eval()
    T = 50
    args = (torch.randn(1, T, 768), torch.tensor([T]), torch.randint(1, 255, (1, T)),
            torch.rand(1, T) * 200 + 100, torch.tensor([0]), torch.randn(1, 192, T))
    names = ['feats', 'p_len', 'pitch', 'pitchf', 'sid', 'rnd']
    torch.onnx.export(net, args, 'pulse_base_f0G40k.onnx', input_names=names, output_names=['audio'],
                      dynamic_axes={'feats': {1: 'T'}, 'pitch': {1: 'T'}, 'pitchf': {1: 'T'},
                                    'rnd': {2: 'T'}, 'audio': {2: 'S'}},
                      opset_version=17, dynamo=False)
    import onnx
    m = onnx.load('pulse_base_f0G40k.onnx')
    meta = {"application": "Pulse", "modelType": "rvc_v2", "samplingRate": SR, "f0": True,
            "embChannels": 768, "embOutputLayer": 12, "useFinalProj": False, "speakers": 109,
            "source": "lj1995/VoiceConversionWebUI pretrained_v2/f0G40k.pth", "license": "MIT"}
    p = m.metadata_props.add(); p.key = 'metadata'; p.value = json.dumps(meta)
    onnx.save(m, 'pulse_base_f0G40k.onnx')
    print('saved')


if __name__ == '__main__':
    main()
