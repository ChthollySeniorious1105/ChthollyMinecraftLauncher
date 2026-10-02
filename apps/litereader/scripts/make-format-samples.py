# 生成新格式的测试样例：ODT、ODP、RTF、OFD、XPS、Markdown 公式、代码
import os, sys, zipfile
from odf.opendocument import OpenDocumentText, OpenDocumentPresentation
from odf.style import Style, TextProperties, ParagraphProperties, MasterPage, PageLayout, PageLayoutProperties
from odf.text import H, P, Span, List, ListItem
from odf.table import Table, TableColumn, TableRow, TableCell
from odf.draw import Page, Frame, TextBox
from odf.namespaces import PRESENTATIONNS

out = sys.argv[1]
os.makedirs(out, exist_ok=True)

# ---------- ODT ----------
doc = OpenDocumentText()
bold = Style(name='Bold', family='text'); bold.addElement(TextProperties(fontweight='bold', color='#c0392b'))
center = Style(name='Center', family='paragraph'); center.addElement(ParagraphProperties(textalign='center'))
doc.automaticstyles.addElement(bold); doc.automaticstyles.addElement(center)
doc.text.addElement(H(outlinelevel=1, text='OpenDocument 文本示例'))
p = P(text='这是一段普通文字，其中包含 '); s = Span(stylename=bold, text='红色粗体'); p.addElement(s); p.addText(' 与继续的文字。')
doc.text.addElement(p)
doc.text.addElement(P(stylename=center, text='居中对齐的段落'))
doc.text.addElement(H(outlinelevel=2, text='列表与表格'))
lst = List()
for t in ['第一项', '第二项', '第三项']:
    li = ListItem(); li.addElement(P(text=t)); lst.addElement(li)
doc.text.addElement(lst)
tbl = Table(name='T1'); tbl.addElement(TableColumn(numbercolumnsrepeated=2))
for row in [['格式', '状态'], ['ODT', '支持'], ['ODP', '支持']]:
    tr = TableRow()
    for v in row:
        tc = TableCell(); tc.addElement(P(text=v)); tr.addElement(tc)
    tbl.addElement(tr)
doc.text.addElement(tbl)
doc.save(os.path.join(out, 'document.odt'))

# ---------- ODP ----------
pres = OpenDocumentPresentation()
pl = PageLayout(name='PL'); pl.addElement(PageLayoutProperties(pagewidth='28cm', pageheight='15.75cm'))
pres.automaticstyles.addElement(pl)
mp = MasterPage(name='Default', pagelayoutname=pl); pres.masterstyles.addElement(mp)
for i, (title, lines) in enumerate([('ODP 演示文稿', ['OpenDocument 格式', 'LiteReader 以大纲方式显示']), ('第二页', ['要点 A', '要点 B', '要点 C'])]):
    page = Page(name=f'page{i+1}', masterpagename=mp)
    f = Frame(width='24cm', height='3cm', x='2cm', y='1cm'); f.setAttrNS(PRESENTATIONNS, 'class', 'title')
    tb = TextBox(); tb.addElement(P(text=title)); f.addElement(tb); page.addElement(f)
    f2 = Frame(width='24cm', height='9cm', x='2cm', y='5cm'); f2.setAttrNS(PRESENTATIONNS, 'class', 'outline')
    tb2 = TextBox()
    for l in lines: tb2.addElement(P(text=l))
    f2.addElement(tb2); page.addElement(f2)
    pres.presentation.addElement(page)
pres.save(os.path.join(out, 'slides.odp'))

# ---------- RTF ----------
rtf = r'''{\rtf1\ansi\ansicpg936\deff0{\fonttbl{\f0\fnil\fcharset134 Microsoft YaHei;}{\f1\fswiss Arial;}}
{\colortbl;\red192\green57\blue43;\red37\green99\blue235;}
\viewkind4\uc1\pard\qc\b\fs40 RTF \'b8\'bb\'ce\'c4\'b1\'be\'ca\'be\'c0\'fd\b0\par
\pard\fs24 \f1 This is \b bold\b0 , \i italic\i0 , \ul underline\ulnone  and \cf1 red\cf0  / \cf2 blue\cf0  text.\par
\f0 \'d6\'d0\'ce\'c4\'b6\'ce\'c2\'e4\'a3\'ba\'d6\'a7\'b3\'d6 GBK \'b1\'e0\'c2\'eb\'a1\'a3\par
\pard\qr Right aligned.\par
}'''
open(os.path.join(out, 'document.rtf'), 'w', encoding='latin-1').write(rtf)

# ---------- OFD（最小可用结构）----------
ofd = zipfile.ZipFile(os.path.join(out, 'document.ofd'), 'w', zipfile.ZIP_DEFLATED)
ns = 'xmlns:ofd="http://www.ofdspec.org/2016"'
ofd.writestr('OFD.xml', f'<?xml version="1.0" encoding="UTF-8"?><ofd:OFD {ns} Version="1.0" DocType="OFD"><ofd:DocBody><ofd:DocInfo><ofd:DocID>1</ofd:DocID><ofd:Title>OFD 示例</ofd:Title></ofd:DocInfo><ofd:DocRoot>Doc_0/Document.xml</ofd:DocRoot></ofd:DocBody></ofd:OFD>')
ofd.writestr('Doc_0/Document.xml', f'<?xml version="1.0" encoding="UTF-8"?><ofd:Document {ns}><ofd:CommonData><ofd:MaxUnitID>20</ofd:MaxUnitID><ofd:PageArea><ofd:PhysicalBox>0 0 210 297</ofd:PhysicalBox></ofd:PageArea><ofd:PublicRes>PublicRes.xml</ofd:PublicRes></ofd:CommonData><ofd:Pages><ofd:Page ID="1" BaseLoc="Pages/Page_0/Content.xml"/><ofd:Page ID="2" BaseLoc="Pages/Page_1/Content.xml"/></ofd:Pages></ofd:Document>')
ofd.writestr('Doc_0/PublicRes.xml', f'<?xml version="1.0" encoding="UTF-8"?><ofd:Res {ns} BaseLoc="Res"><ofd:Fonts><ofd:Font ID="2" FontName="宋体" FamilyName="SimSun"/><ofd:Font ID="3" FontName="黑体" FamilyName="SimHei"/></ofd:Fonts></ofd:Res>')
def page(title, body, n):
    return f'''<?xml version="1.0" encoding="UTF-8"?><ofd:Page {ns}><ofd:Content><ofd:Layer ID="{n}0">
<ofd:TextObject ID="{n}1" Boundary="20 20 170 14" Font="3" Size="8"><ofd:FillColor Value="185 28 28"/><ofd:TextCode X="0" Y="9">{title}</ofd:TextCode></ofd:TextObject>
<ofd:PathObject ID="{n}2" Boundary="20 36 170 1" Stroke="true" LineWidth="0.6"><ofd:StrokeColor Value="185 28 28"/><ofd:AbbreviatedData>M 0 0.5 L 170 0.5</ofd:AbbreviatedData></ofd:PathObject>
<ofd:TextObject ID="{n}3" Boundary="20 45 170 10" Font="2" Size="4.5"><ofd:TextCode X="0" Y="6">{body}</ofd:TextCode></ofd:TextObject>
<ofd:PathObject ID="{n}4" Boundary="20 70 60 30" Fill="true" Stroke="false"><ofd:FillColor Value="37 99 235"/><ofd:AbbreviatedData>M 0 0 L 60 0 L 60 30 L 0 30 C</ofd:AbbreviatedData></ofd:PathObject>
</ofd:Layer></ofd:Content></ofd:Page>'''
ofd.writestr('Doc_0/Pages/Page_0/Content.xml', page('OFD 版式文档示例', '国家标准 GB/T 33190 电子文件存储与交换格式', 1))
ofd.writestr('Doc_0/Pages/Page_1/Content.xml', page('第二页', '文字、线条与矩形均为矢量绘制', 2))
ofd.close()

# ---------- XPS（最小可用结构）----------
xps = zipfile.ZipFile(os.path.join(out, 'document.xps'), 'w', zipfile.ZIP_DEFLATED)
xps.writestr('[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="fdseq" ContentType="application/vnd.ms-package.xps-fixeddocumentsequence+xml"/><Default Extension="fdoc" ContentType="application/vnd.ms-package.xps-fixeddocument+xml"/><Default Extension="fpage" ContentType="application/vnd.ms-package.xps-fixedpage+xml"/><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/></Types>')
xps.writestr('_rels/.rels', '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Type="http://schemas.microsoft.com/xps/2005/06/fixedrepresentation" Target="/FixedDocSeq.fdseq" Id="R0"/></Relationships>')
xps.writestr('FixedDocSeq.fdseq', '<FixedDocumentSequence xmlns="http://schemas.microsoft.com/xps/2005/06"><DocumentReference Source="Documents/1/FixedDoc.fdoc"/></FixedDocumentSequence>')
xps.writestr('Documents/1/FixedDoc.fdoc', '<FixedDocument xmlns="http://schemas.microsoft.com/xps/2005/06"><PageContent Source="Pages/1.fpage" Width="816" Height="1056"/></FixedDocument>')
xps.writestr('Documents/1/Pages/1.fpage', '<FixedPage xmlns="http://schemas.microsoft.com/xps/2005/06" Width="816" Height="1056" xml:lang="zh-CN"><Path Data="M 60,60 L 756,60 L 756,140 L 60,140 Z" Fill="#FF0EA5E9"/><Glyphs OriginX="80" OriginY="115" FontRenderingEmSize="36" UnicodeString="XPS Document Sample" Fill="#FFFFFFFF"/><Glyphs OriginX="80" OriginY="220" FontRenderingEmSize="20" UnicodeString="XPS 文档示例：文字与矢量图形" Fill="#FF1F2937"/><Path Data="M 80,260 L 400,260" Stroke="#FFB91C1C" StrokeThickness="3"/></FixedPage>')
xps.close()

# ---------- Markdown 公式 + 代码 ----------
open(os.path.join(out, 'math.md'), 'w', encoding='utf-8').write(r'''# Markdown 公式与代码

行内公式 $E=mc^2$，以及 \(a_1 + b_1\)。价格 $5 和 $10 不应被识别为公式。

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$

```python
def fib(n):
    return n if n < 2 else fib(n - 1) + fib(n - 2)
```

```math
\sum_{k=1}^{n} k = \frac{n(n+1)}{2}
```

行内代码 `$not_math$` 不应被渲染。
''')
open(os.path.join(out, 'code.py'), 'w', encoding='utf-8').write('''# 代码高亮示例
import math


class Circle:
    """圆形"""

    def __init__(self, r: float):
        self.r = r

    def area(self) -> float:
        return math.pi * self.r ** 2


if __name__ == "__main__":
    print(f"面积 = {Circle(2).area():.2f}")
''')
print('ok')
