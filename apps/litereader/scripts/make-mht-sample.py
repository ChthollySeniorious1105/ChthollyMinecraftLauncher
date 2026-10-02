import base64, sys
img = open(sys.argv[2], 'rb').read()
html = '''<html><head><meta charset="utf-8"><title>MHT 归档样例</title>
<style>body{font-family:sans-serif;margin:40px}h1{color:#0ea5e9}.bg{background:url("http://mht.local/bg.png") no-repeat;padding:20px;height:80px}</style></head>
<body><h1>MHT 网页归档</h1><p>这张图片来自归档内部（Content-Location）：</p>
<img src="http://mht.local/pic.png" width="300"><div class="bg">CSS 背景图</div>
<p>中文内容以 quoted-printable 编码。</p></body></html>'''
qp = ''
import quopri
qp = quopri.encodestring(html.encode('utf-8')).decode('ascii')
b64 = base64.encodebytes(img).decode('ascii')
mht = f'''From: <Saved by LiteReader>
Subject: MHT sample
MIME-Version: 1.0
Content-Type: multipart/related;
\ttype="text/html";
\tboundary="----=_NextPart_000"

This is a multi-part message in MIME format.

------=_NextPart_000
Content-Type: text/html; charset="utf-8"
Content-Transfer-Encoding: quoted-printable
Content-Location: http://mht.local/index.html

{qp}
------=_NextPart_000
Content-Type: image/png
Content-Transfer-Encoding: base64
Content-Location: http://mht.local/pic.png

{b64}
------=_NextPart_000
Content-Type: image/png
Content-Transfer-Encoding: base64
Content-Location: http://mht.local/bg.png

{b64}
------=_NextPart_000--
'''
open(sys.argv[1], 'w', newline='\r\n', encoding='ascii').write(mht)
print('ok')
