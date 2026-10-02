import ctypes as C, json, time, numpy as np, soundfile as sf, librosa, sys
import os, subprocess
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
D=os.path.join(ROOT,'_build','native').replace(os.sep,'/')+'/'
SPEECH=os.path.join(ROOT,'_build','speech.wav')
if not os.path.exists(SPEECH):  # synthesize a test utterance with Windows TTS (48 kHz mono)
    ps=("Add-Type -AssemblyName System.Speech; $s=New-Object System.Speech.Synthesis.SpeechSynthesizer; "
        "$f=New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(48000,[System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,[System.Speech.AudioFormat.AudioChannel]::Mono); "
        f"$s.SetOutputToWaveFile('{SPEECH}',$f); $s.Speak('Hello everyone, this is a test of the Pulse voice changer. The quick brown fox jumps over the lazy dog.'); $s.Dispose()")
    subprocess.run(['powershell','-NoProfile','-Command',ps],check=True)
lib=C.CDLL(D+'pulse_native.dll')
CB=C.CFUNCTYPE(None,C.c_int32,C.c_int32,C.c_int32,C.POINTER(C.c_uint8),C.c_int32)
events=[]
@CB
def cb(t,a,b,d,n):
    data=bytes(d[:n]) if n>0 else b''
    if d: lib.pn_free(d)
    events.append((t,a,b,data))
    if t==6: print('  [log]',a,data.decode('utf-8','replace'))
    if t==5: print('  [vc]',data.decode())
lib.pn_init.argtypes=[CB,C.c_char_p]
for f in ['pn_list_devices','pn_gpu_info','pn_vc_status','pn_key_name']: getattr(lib,f).restype=C.c_void_p
lib.pn_free.argtypes=[C.c_void_p]
def js(p): s=C.cast(p,C.c_char_p).value.decode(); lib.pn_free(p); return json.loads(s) if s[:1] in '[{' else s
print('abi',lib.pn_abi_version(),'init',lib.pn_init(cb,D.encode()))
print('mics',[d['name'] for d in js(lib.pn_list_devices(0))])
print('speakers',[d['name'] for d in js(lib.pn_list_devices(1))])
g=js(lib.pn_gpu_info()); print('ort',g['ort'],g['ortError']); [print('  adapter',a) for a in g['adapters']]; [print('  provider',p['id'],p['label']) for p in g['providers']]
lib.pn_key_name.argtypes=[C.c_int32]; print('keys',[js(lib.pn_key_name(k)) for k in [0x56,0x14,0x05,0x70,0xC0,0x11]])
# --- denoise test: speech + noise
x,sr=sf.read(SPEECH); x=x.astype(np.float32)*0.5
rng=np.random.default_rng(0); noise=(rng.standard_normal(len(x))*0.03).astype(np.float32)
hum=(0.03*np.sin(2*np.pi*120*np.arange(len(x))/48000)).astype(np.float32)
noisy=x+noise+hum
def run(inp):
    out=np.zeros_like(inp); n=lib.pn_debug_process(inp.ctypes.data_as(C.POINTER(C.c_float)),len(inp),out.ctypes.data_as(C.POINTER(C.c_float))); return out[:n]
lib.pn_set_noise_suppression.argtypes=[C.c_int32]
def snr_like(y):
    # energy where clean is silent vs where it speaks
    e=librosa.feature.rms(y=x[:len(y)],frame_length=960,hop_length=960)[0]; o=librosa.feature.rms(y=y,frame_length=960,hop_length=960)[0]
    L=min(len(e),len(o)); sil=e[:L]<0.003; sp=e[:L]>0.02
    return 20*np.log10(o[:L][sp].mean()/max(o[:L][sil].mean(),1e-6))
for lv in [0,1,2,3]:
    lib.pn_set_noise_suppression(lv); y=run(noisy.copy()); sf.write(os.path.join(ROOT,'_build',f'ns{lv}.wav'),y,48000)
    print('ns level',lv,'speech/silence ratio %.1f dB'%snr_like(y))
# --- DSP voice changer
lib.pn_set_noise_suppression(2); lib.pn_vc_set_mode(1); lib.pn_vc_set_pitch.argtypes=[C.c_float]; lib.pn_vc_set_pitch(5.0)
y=run(x.copy()); sf.write(os.path.join(ROOT,'_build','dsp_p5.wav'),y,48000)
f0i=librosa.yin(x[:96000],fmin=60,fmax=600,sr=48000); f0o=librosa.yin(y[:96000],fmin=60,fmax=600,sr=48000)
print('DSP pitch +5: median in %.0f out %.0f (expect x%.2f)'%(np.median(f0i),np.median(f0o),2**(5/12)))
# --- AI voice changer (inline)
lib.pn_vc_set_mode(0); lib.pn_vc_set_pitch(0.0)
lib.pn_debug_inline(1)
lib.pn_vc_ai_config.argtypes=[C.c_char_p,C.c_char_p,C.c_int32,C.c_int32,C.c_int32]
prov=sys.argv[1] if len(sys.argv)>1 else 'auto'
lib.pn_vc_ai_config(prov.encode(),b'',200,300,0)
t=time.time()
while True:
    st=js(lib.pn_vc_status())
    if st['state'] in (2,3) or time.time()-t>120: break
    time.sleep(0.2)
print('AI state',st)
if st['state']==2:
    lib.pn_vc_set_mode(2); lib.pn_vc_set_pitch(12.0)
    t=time.time(); y=run(x.copy()); dt=time.time()-t
    sf.write(os.path.join(ROOT,'_build','ai_p12.wav'),y,48000)
    print('AI: processed %.1fs audio in %.1fs (RTF %.2f)'%(len(x)/48000,dt,dt/(len(x)/48000)), js(lib.pn_vc_status()))
    v=y[48000:]; print('out rms %.3f max %.3f finite %s'%(np.sqrt((v**2).mean()),np.abs(v).max(),np.isfinite(v).all()))
    f0o=librosa.yin(y[48000:48000*4],fmin=60,fmax=1000,sr=48000); f0i=librosa.yin(x[48000:48000*4],fmin=60,fmax=1000,sr=48000)
    print('AI pitch +12: median in %.0f out %.0f'%(np.median(f0i),np.median(f0o)))
lib.pn_shutdown(); print('shutdown ok')
