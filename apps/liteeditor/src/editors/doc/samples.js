// 文档示例
export const SAMPLES = {
    report: {
        page: { lineHeight: 1.75 },
        html: `
<h1 class="doc-title">2026 年度产品研发报告</h1>
<p class="doc-subtitle">LiteEditor 项目组 · 2026 年 9 月</p>
<nav class="doc-toc" contenteditable="false"></nav>
<h1>一、项目概述</h1>
<p style="text-indent:2em">LiteEditor 是一款轻量级的全能编辑器，集成了<b>图像编辑</b>、<b>几何画板</b>、<b>文字处理</b>、<b>电子表格</b>与<b>演示文稿</b>五大模块。所有文件均在本地处理，无需联网，也不依赖任何外部软件。</p>
<p style="text-indent:2em">本报告总结了本年度的研发进展、关键指标以及下一阶段的工作计划。</p>
<h2>1.1 目标</h2>
<ul><li>启动时间控制在 <span style="color:#dc2626"><b>1 秒</b></span>以内</li><li>支持主流办公文件格式的读写：DOCX、XLSX、PPTX、PDF、LaTeX</li><li>界面统一、支持 36 款主题<ul><li>明暗模式一键切换</li><li>编辑区保持真实纸张颜色</li></ul></li></ul>
<h2>1.2 里程碑</h2>
<ol><li>第一季度：完成应用框架与主题系统</li><li>第二季度：完成五大编辑器的基础功能</li><li>第三季度：完善文件格式兼容性</li></ol>
<h1>二、关键指标</h1>
<table><tbody>
<tr><th>指标</th><th>目标</th><th>实际</th><th>完成率</th></tr>
<tr><td>冷启动时间</td><td>1.0 s</td><td>0.8 s</td><td style="background-color:#dcfce7">125%</td></tr>
<tr><td>DOCX 兼容用例</td><td>200</td><td>186</td><td style="background-color:#fef9c3">93%</td></tr>
<tr><td>公式函数数量</td><td>60</td><td>72</td><td style="background-color:#dcfce7">120%</td></tr>
</tbody></table>
<h2>2.1 性能模型</h2>
<p style="text-indent:2em">渲染耗时可以近似表示为可见单元格数量的线性函数：</p>
<div class="doc-math-block"><span class="doc-math block" data-tex="T(n) = T_0 + k\\cdot n, \\quad n = \\left\\lceil \\frac{H}{h} \\right\\rceil \\times \\left\\lceil \\frac{W}{w} \\right\\rceil" contenteditable="false"></span></div>
<p style="text-indent:2em">其中 <span class="doc-math" data-tex="T_0" contenteditable="false"></span> 为固定开销，<span class="doc-math" data-tex="k" contenteditable="false"></span> 为每个单元格的平均绘制时间。</p>
<blockquote>虚拟滚动使渲染耗时与表格总行数无关，只与窗口大小有关。</blockquote>
<h1>三、下一步计划</h1>
<ul class=""><li class="task done">完成 LaTeX 文件的打开与保存</li><li class="task">完善 PSD 图层样式</li><li class="task">增加协同编辑</li></ul>
<pre>npm install
npm run dev</pre>
<p><br></p>`,
    },
    letter: {
        page: { lineHeight: 2 },
        html: `
<p>尊敬的王经理：</p>
<p style="text-indent:2em">您好！</p>
<p style="text-indent:2em">感谢贵公司长期以来对我们工作的支持与信任。现就双方合作的新项目事宜致函如下：</p>
<p style="text-indent:2em">一、项目预计于 2026 年 10 月启动，周期约六个月；</p>
<p style="text-indent:2em">二、我方将派出五名工程师组成专项小组，负责需求分析与系统开发；</p>
<p style="text-indent:2em">三、具体合作条款详见附件《合作协议（草案）》。</p>
<p style="text-indent:2em">如有任何疑问，欢迎随时与我联系。期待与贵公司的进一步合作！</p>
<p style="text-indent:2em">此致</p>
<p>敬礼！</p>
<p><br></p>
<p style="text-align:right">LiteEditor 项目组</p>
<p style="text-align:right">张　明</p>
<p style="text-align:right">2026 年 9 月 28 日</p>`,
    },
}
