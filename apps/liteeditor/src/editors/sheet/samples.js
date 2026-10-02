// 电子表格示例：家庭预算、成绩统计
import { Sheet, makeCell, internStyle } from './model.js'
import { parseInput } from './editing.js'

// 按行写入：rows = [[值或公式文本, …]]，styles 按列（或 (r,c) => style）
function fillSheet(sh, rows, r0 = 0, c0 = 0, styleFn) {
    rows.forEach((row, i) => row.forEach((t, j) => {
        if (t == null || t === '') { const s = styleFn?.(r0 + i, c0 + j); if (s) sh.set(r0 + i, c0 + j, { s }); return }
        const p = typeof t === 'number' ? { v: t } : parseInput(String(t))
        let s = styleFn?.(r0 + i, c0 + j) ?? null
        if (p.fmt) s = internStyle({ ...(s ?? {}), fmt: p.fmt })
        sh.set(r0 + i, c0 + j, makeCell(p.v, p.f, s))
    }))
}

const S = o => internStyle(o)
const BORDER = 'thin #c7ccd4'
const box = o => S({ bt: BORDER, bb: BORDER, bl: BORDER, br: BORDER, ...o })

export function buildSample(ed, name) {
    if (name === 'budget') return budget(ed)
    if (name === 'grades') return grades(ed)
    ed.book.sheets.push(new Sheet('Sheet1'))
}

function budget(ed) {
    const sh = new Sheet('2026 年预算')
    const title = S({ sz: 18, b: true, color: '#1f4e79' })
    const head = box({ b: true, fill: '#1f4e79', color: '#ffffff', ha: 'center' })
    const money = box({ fmt: '"¥"#,##0' })
    const total = box({ b: true, fill: '#deebf7', fmt: '"¥"#,##0' })
    const label = box({})
    const totalLabel = box({ b: true, fill: '#deebf7' })
    fillSheet(sh, [['2026 年家庭月度预算']], 0, 0, () => title)
    fillSheet(sh, [['单位：元　·　修改 B~G 列的金额，合计、差额与图表会自动更新']], 1, 0, () => S({ color: '#64748b' }))
    const months = ['1 月', '2 月', '3 月', '4 月', '5 月', '6 月']
    fillSheet(sh, [['项目', ...months, '合计', '月均', '占比']], 3, 0, () => head)
    const items = [
        ['工资收入', 18000, 18000, 18500, 18500, 18500, 19000],
        ['房租 / 房贷', 5200, 5200, 5200, 5200, 5200, 5200],
        ['餐饮', 2600, 3100, 2450, 2380, 2720, 2550],
        ['交通', 520, 460, 610, 480, 530, 590],
        ['水电燃气', 380, 420, 310, 260, 290, 460],
        ['教育培训', 1200, 800, 800, 1500, 800, 800],
        ['娱乐休闲', 900, 1600, 700, 850, 1200, 1500],
        ['医疗保险', 450, 450, 450, 450, 450, 450],
    ]
    items.forEach((row, i) => {
        const r = 4 + i, R = r + 1
        fillSheet(sh, [[...row, `=SUM(B${R}:G${R})`, `=AVERAGE(B${R}:G${R})`, i === 0 ? '' : `=H${R}/$H$13`]], r, 0, (rr, c) => c === 0 ? label : c === 9 ? box({ fmt: '0.0%' }) : money)
    })
    // 汇总行
    fillSheet(sh, [['支出合计', ...months.map((_, j) => `=SUM(${'BCDEFG'[j]}6:${'BCDEFG'[j]}12)`), '=SUM(H6:H12)', '=AVERAGE(B13:G13)', '']], 12, 0, (r, c) => c === 0 ? totalLabel : total)
    fillSheet(sh, [['结余', ...months.map((_, j) => `=${'BCDEFG'[j]}5-${'BCDEFG'[j]}13`), '=H5-H13', '=AVERAGE(B14:G14)', '=H14/H5']], 13, 0, (r, c) => c === 0 ? totalLabel : c === 9 ? box({ b: true, fill: '#deebf7', fmt: '0.0%' }) : total)
    fillSheet(sh, [['储蓄目标', 5000, '', '是否达标', '=IF(I14>=B16,"✔ 已达标","✘ 未达标")']], 15, 0, (r, c) => c === 0 || c === 3 ? S({ b: true }) : c === 1 ? S({ fmt: '"¥"#,##0' }) : null)
    const colW = new Map([[0, 110], ...[1, 2, 3, 4, 5, 6].map(c => [c, 78]), [7, 96], [8, 90], [9, 70]])
    sh.setMeta({
        colW, rowH: new Map([[0, 36], [3, 28]]), freeze: { r: 4, c: 1 }, merges: [{ r1: 0, c1: 0, r2: 0, c2: 9 }],
        cf: [
            { id: 'cf1', range: { r1: 13, c1: 1, r2: 13, c2: 6 }, type: 'lt', a: 5000, style: { fill: '#fde2e4', color: '#9c0006' } },
            { id: 'cf2', range: { r1: 13, c1: 1, r2: 13, c2: 6 }, type: 'ge', a: 5000, style: { fill: '#d9f2dc', color: '#006100' } },
            { id: 'cf3', range: { r1: 5, c1: 7, r2: 11, c2: 7 }, type: 'bar', color: '#5b9bd5' },
        ],
        charts: [
            { id: 'ch1', kind: 'bar', title: '每月收支', sheet: sh.name, range: { r1: 3, c1: 0, r2: 13, c2: 6 }, rows: [4, 12, 13], x: 30, y: 460, w: 470, h: 280, legend: true, byRow: true },
            { id: 'ch2', kind: 'pie', title: '支出构成', sheet: sh.name, range: { r1: 5, c1: 0, r2: 11, c2: 0 }, x: 520, y: 460, w: 420, h: 280, legend: true },
        ],
    })
    // 饼图使用“项目 + 合计”两列：通过数据区域 A6:A12 与 H6:H12 —— 这里直接用 A:H 的首列与合计列
    sh.setMeta({ charts: sh.meta.charts.map(c => c.id === 'ch2' ? { ...c, range: { r1: 5, c1: 7, r2: 11, c2: 7 }, labelsRange: { r1: 5, c1: 0, r2: 11, c2: 0 } } : c) })
    ed.book.sheets.push(sh)
}

function grades(ed) {
    const sh = new Sheet('期中成绩')
    const head = box({ b: true, fill: '#375623', color: '#ffffff', ha: 'center' })
    const cell = box({ ha: 'center' })
    const num = box({ ha: 'center' })
    fillSheet(sh, [['高一（3）班 期中考试成绩']], 0, 0, () => S({ sz: 16, b: true, color: '#375623' }))
    fillSheet(sh, [['学号', '姓名', '语文', '数学', '英语', '物理', '化学', '总分', '平均分', '名次', '等级']], 2, 0, () => head)
    const students = [
        ['张伟', 92, 98, 88, 95, 90], ['王芳', 88, 76, 95, 70, 82], ['李娜', 79, 91, 84, 88, 93], ['刘洋', 95, 85, 90, 78, 80],
        ['陈静', 68, 72, 75, 65, 70], ['杨磊', 84, 99, 80, 97, 96], ['赵敏', 91, 83, 97, 76, 85], ['黄强', 73, 64, 70, 82, 68],
        ['周杰', 86, 90, 78, 91, 88], ['吴婷', 97, 87, 93, 84, 90], ['徐明', 62, 58, 66, 71, 60], ['孙丽', 80, 88, 86, 79, 83],
    ]
    const n = students.length, last = 3 + n
    students.forEach((s, i) => {
        const R = 4 + i
        fillSheet(sh, [[`2026${String(i + 1).padStart(3, '0')}`, ...s, `=SUM(C${R}:G${R})`, `=ROUND(AVERAGE(C${R}:G${R}),1)`, `=RANK(H${R},$H$4:$H$${last})`,
            `=IF(I${R}>=90,"优秀",IF(I${R}>=80,"良好",IF(I${R}>=60,"及格","不及格")))`]], 3 + i, 0, (r, c) => c === 1 ? box({}) : c === 8 ? box({ ha: 'center', fmt: '0.0' }) : c <= 9 ? num : cell)
    })
    const sum = r => (r0, c) => c === 0 ? box({ b: true, fill: '#e2efda' }) : box({ b: true, fill: '#e2efda', ha: 'center', fmt: r === 'avg' ? '0.0' : undefined })
    const L = last
    fillSheet(sh, [['平均分', '', ...'CDEFGHI'.split('').map(c => `=AVERAGE(${c}4:${c}${L})`), '', '']], L, 0, sum('avg'))
    fillSheet(sh, [['最高分', '', ...'CDEFGHI'.split('').map(c => `=MAX(${c}4:${c}${L})`), '', '']], L + 1, 0, sum())
    fillSheet(sh, [['及格率', '', ...'CDEFG'.split('').map(c => `=COUNTIF(${c}4:${c}${L},">=60")/COUNT(${c}4:${c}${L})`), '', '', '', '']], L + 2, 0, (r, c) => c === 0 ? box({ b: true, fill: '#e2efda' }) : box({ b: true, fill: '#e2efda', ha: 'center', fmt: '0%' }))
    fillSheet(sh, [['查询：', '杨磊', '的数学成绩：', '', `=VLOOKUP(B${L + 5},B4:G${L},3,FALSE)`]], L + 4, 0, (r, c) => c === 1 ? S({ fill: '#fff2c7', b: true }) : c === 4 ? S({ b: true, color: '#c00000' }) : null)
    sh.setMeta({
        colW: new Map([[0, 92], [1, 70], ...[2, 3, 4, 5, 6].map(c => [c, 56]), [7, 64], [8, 64], [9, 56], [10, 70]]),
        rowH: new Map([[0, 32], [2, 28]]), freeze: { r: 3, c: 2 },
        merges: [{ r1: 0, c1: 0, r2: 0, c2: 10 }, { r1: L, c1: 0, r2: L, c2: 1 }, { r1: L + 1, c1: 0, r2: L + 1, c2: 1 }, { r1: L + 2, c1: 0, r2: L + 2, c2: 1 }],
        cf: [
            { id: 'g1', range: { r1: 3, c1: 2, r2: L - 1, c2: 6 }, type: 'lt', a: 60, style: { fill: '#fde2e4', color: '#9c0006', b: true } },
            { id: 'g2', range: { r1: 3, c1: 2, r2: L - 1, c2: 6 }, type: 'ge', a: 95, style: { fill: '#d9f2dc', color: '#006100' } },
            { id: 'g3', range: { r1: 3, c1: 7, r2: L - 1, c2: 7 }, type: 'scale', colors: ['#f8696b', '#ffeb84', '#63be7b'] },
            { id: 'g4', range: { r1: 3, c1: 10, r2: L - 1, c2: 10 }, type: 'eq', a: '优秀', style: { color: '#006100', b: true } },
        ],
        charts: [{ id: 'gc', kind: 'bar', title: '各科平均分', sheet: sh.name, range: { r1: 2, c1: 2, r2: 2, c2: 6 }, valuesRange: { r1: L, c1: 2, r2: L, c2: 6 }, x: 780, y: 110, w: 400, h: 260, legend: false }],
        filter: { range: { r1: 2, c1: 0, r2: L - 1, c2: 10 }, cols: {}, hidden: new Set() },
    })
    ed.book.sheets.push(sh)
}
