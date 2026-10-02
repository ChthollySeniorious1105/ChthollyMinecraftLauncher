// 数据操作：填充柄、排序、筛选、查找替换、删除重复项
import { h, toast, dialog, formDialog } from '../../core/dom.js'
import { openMenu } from '../../core/menu.js'
import { icon } from '../../core/icons.js'
import { MAX_COLS, colName, inRange } from './addr.js'
import { makeCell } from './model.js'
import { shiftFormula } from './formula/lexer.js'
import { compare, isErr } from './formula/values.js'
import { display } from './format.js'

// 序列识别：数字等差、日期、文本+数字（项目1、项目2）、星期、月份
const SERIES = [
    ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'],
    ['周一', '周二', '周三', '周四', '周五', '周六', '周日'],
    ['一月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '十一月', '十二月'],
    ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
    ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
    ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'],
    ['第一季度', '第二季度', '第三季度', '第四季度'],
    ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'],
    ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'],
]

// 根据源值序列生成第 k 个（k 从 0 起，相对于序列末尾之后）
function seriesGen(src, copyOnly) {
    const n = src.length
    const vals = src.map(c => c?.v)
    if (copyOnly || src.some(c => c?.f)) return null
    // 纯数字
    if (vals.every(v => typeof v === 'number')) {
        if (n === 1) return k => vals[0] + k + 1
        const step = (vals[n - 1] - vals[0]) / (n - 1)
        const linear = vals.every((v, i) => Math.abs(v - (vals[0] + step * i)) < 1e-9)
        if (!linear) {
            // 最小二乘拟合
            const mx = (n - 1) / 2, my = vals.reduce((a, b) => a + b, 0) / n
            let num = 0, den = 0
            vals.forEach((v, i) => { num += (i - mx) * (v - my); den += (i - mx) ** 2 })
            const b = num / den, a = my - b * mx
            return k => +(a + b * (n + k)).toPrecision(15)
        }
        return k => +(vals[n - 1] + step * (k + 1)).toPrecision(15)
    }
    if (vals.every(v => typeof v === 'string')) {
        // 内置序列
        for (const list of SERIES) {
            const idx = vals.map(v => list.indexOf(v))
            if (idx.every(i => i >= 0)) {
                const step = n > 1 ? idx[1] - idx[0] : 1
                return k => list[((idx[n - 1] + step * (k + 1)) % list.length + list.length) % list.length]
            }
        }
        // 文本 + 数字
        const parts = vals.map(v => /^(.*?)(\d+)(\D*)$/.exec(v))
        if (parts.every(p => p) && parts.every(p => p[1] === parts[0][1] && p[3] === parts[0][3])) {
            const nums = parts.map(p => +p[2])
            const step = n > 1 ? nums[n - 1] - nums[n - 2] : 1
            const width = parts[0][2].startsWith('0') ? parts[0][2].length : 0
            return k => parts[0][1] + String(Math.max(0, nums[n - 1] + step * (k + 1))).padStart(width, '0') + parts[0][3]
        }
    }
    return null
}

export const DataOps = {
    // ---------- 填充 ----------
    fillRange(g, t, { copyOnly = false } = {}) {
        const sh = this.sheet
        const down = t.r2 > g.r2, up = t.r1 < g.r1, right = t.c2 > g.c2, left = t.c1 < g.c1
        if (!down && !up && !right && !left) {
            // 向内拖动：清除
            if (t.r2 < g.r2 || t.c2 < g.c2) {
                this.batch('清除', set => sh.cells.each((r, c, cell) => {
                    if ((r > t.r2 || c > t.c2) && (cell.v != null || cell.f)) set(r, c, cell.s ? { s: cell.s } : null)
                }, g.r1, g.c1, g.r2, g.c2))
                this.selectRange(t)
            }
            return
        }
        const vertical = down || up
        this.batch('填充', set => {
            const lines = vertical ? [g.c1, g.c2] : [g.r1, g.r2]
            for (let L = lines[0]; L <= lines[1]; L++) {
                const src = []
                const len = vertical ? g.r2 - g.r1 + 1 : g.c2 - g.c1 + 1
                for (let i = 0; i < len; i++) src.push(vertical ? sh.get(g.r1 + i, L) : sh.get(L, g.c1 + i))
                const forward = down || right
                const seq = forward ? src : [...src].reverse()
                const gen = seriesGen(seq, copyOnly)
                const total = vertical ? (down ? t.r2 - g.r2 : g.r1 - t.r1) : (right ? t.c2 - g.c2 : g.c1 - t.c1)
                for (let k = 0; k < total; k++) {
                    const off = forward ? len + k : -(k + 1)
                    const srcIdx = forward ? k % len : len - 1 - (k % len)
                    const cell = src[srcIdx]
                    const r = vertical ? g.r1 + off : L, c = vertical ? L : g.c1 + off
                    let nc
                    if (cell?.f) {
                        const sr = vertical ? g.r1 + srcIdx : L, scol = vertical ? L : g.c1 + srcIdx
                        nc = { ...cell, f: shiftFormula(cell.f, r - sr, c - scol) }
                    } else if (gen && cell?.v != null) nc = makeCell(gen(k), null, cell.s)
                    else nc = cell ?? null
                    set(r, c, nc)
                }
            }
        })
        this.selectRange({ r1: Math.min(g.r1, t.r1), c1: Math.min(g.c1, t.c1), r2: Math.max(g.r2, t.r2), c2: Math.max(g.c2, t.c2) })
    },

    // 双击填充柄：按相邻列的数据长度向下填充
    fillDownAuto() {
        const g = this.range, sh = this.sheet
        const probe = c => { let r = g.r2; while (r + 1 < 1048576 && sh.get(r + 1, c) && (sh.get(r + 1, c).v != null || sh.get(r + 1, c).f)) r++; return r }
        let end = g.r2
        if (g.c1 > 0) end = Math.max(end, probe(g.c1 - 1))
        if (end === g.r2 && g.c2 < MAX_COLS - 1) end = Math.max(end, probe(g.c2 + 1))
        if (end > g.r2) this.fillRange(g, { ...g, r2: end })
    },

    // Ctrl+D / Ctrl+R
    fillDir(dir) {
        const g = this.clampUsedForWrite(this.range)
        if (dir === 'down') {
            if (g.r1 === g.r2) { if (g.r1 === 0) return; this.fillRange({ ...g, r1: g.r1 - 1, r2: g.r1 - 1 }, { ...g, r1: g.r1 - 1 }, { copyOnly: true }) }
            else this.fillRange({ ...g, r2: g.r1 }, g, { copyOnly: true })
        } else {
            if (g.c1 === g.c2) { if (g.c1 === 0) return; this.fillRange({ ...g, c1: g.c1 - 1, c2: g.c1 - 1 }, { ...g, c1: g.c1 - 1 }, { copyOnly: true }) }
            else this.fillRange({ ...g, c2: g.c1 }, g, { copyOnly: true })
        }
    },

    // ---------- 排序 ----------
    // 自动确定数据区域：选区为单个单元格时扩展到当前连续区域
    currentRegion(r, c) {
        const sh = this.sheet
        const filled = (rr, cc) => { const x = sh.get(rr, cc); return x && (x.v != null || x.f) }
        let g = { r1: r, c1: c, r2: r, c2: c }
        let grow = true
        while (grow) {
            grow = false
            const test = (rr, cc) => rr >= 0 && cc >= 0 && filled(rr, cc)
            for (let cc = g.c1 - 1; cc <= g.c2 + 1; cc++) {
                if (test(g.r1 - 1, cc)) { g.r1--; grow = true; break }
                if (test(g.r2 + 1, cc)) { g.r2++; grow = true; break }
            }
            if (grow) continue
            for (let rr = g.r1 - 1; rr <= g.r2 + 1; rr++) {
                if (test(rr, g.c1 - 1)) { g.c1--; grow = true; break }
                if (test(rr, g.c2 + 1)) { g.c2++; grow = true; break }
            }
        }
        return g
    },
    sortTarget() {
        const g = this.range
        // 活动单元格位于筛选区域内：按筛选区域排序（标题行不参与）
        const f = this.sheet.meta.filter?.range
        if (f && g.r1 === g.r2 && g.c1 === g.c2 && inRange(f, g.r1, g.c1)) return { range: f, header: true }
        if (g.r1 === g.r2 && g.c1 === g.c2) {
            const reg = this.currentRegion(g.r1, g.c1)
            // 判断首行是否为标题：首行全是文本而第二行有数字
            const sh = this.sheet
            let header = false
            if (reg.r2 > reg.r1) {
                let txt = 0, num2 = 0
                for (let c = reg.c1; c <= reg.c2; c++) {
                    const a = this.valueOf(sh, reg.r1, c), b = this.valueOf(sh, reg.r1 + 1, c)
                    if (typeof a === 'string') txt++
                    if (typeof b === 'number') num2++
                }
                header = txt === reg.c2 - reg.c1 + 1 && num2 > 0 || (sh.styleAt(reg.r1, reg.c1)?.b && !sh.styleAt(reg.r1 + 1, reg.c1)?.b)
            }
            return { range: reg, header }
        }
        const u = this.clampUsed(g)
        return { range: u, header: false }
    },

    // keys: [{ c, desc }]
    sortRange(range, keys, header, label = '排序') {
        const sh = this.sheet
        if (this.sheet.meta.merges.some(m => m.r2 >= range.r1 + (header ? 1 : 0) && m.r1 <= range.r2 && m.c2 >= range.c1 && m.c1 <= range.c2 && m.r1 !== m.r2)) {
            return toast('区域中包含跨行合并单元格，无法排序', 'warn')
        }
        const r0 = range.r1 + (header ? 1 : 0)
        const rows = []
        for (let r = r0; r <= range.r2; r++) {
            if (this.grid.rows.isHidden(r) && sh.meta.filter) continue
            const cells = []
            for (let c = range.c1; c <= range.c2; c++) cells.push(sh.get(r, c))
            rows.push({ r, cells, keys: keys.map(k => this.valueOf(sh, r, k.c)) })
        }
        const visibleRows = rows.map(x => x.r)
        rows.sort((a, b) => {
            for (let i = 0; i < keys.length; i++) {
                const x = a.keys[i], y = b.keys[i]
                const ex = x == null || x === '', ey = y == null || y === ''
                if (ex || ey) { if (ex && ey) continue; return ex ? 1 : -1 } // 空值总在最后
                if (isErr(x) || isErr(y)) { if (isErr(x) && isErr(y)) continue; return isErr(x) ? 1 : -1 }
                const c = typeof x === 'string' && typeof y === 'string' ? x.localeCompare(y, 'zh-CN', { numeric: true }) : compare(x, y)
                if (c) return keys[i].desc ? -c : c
            }
            return a.r - b.r
        })
        this.batch(label, set => {
            rows.forEach((row, i) => {
                const tr = visibleRows[i]
                row.cells.forEach((cell, j) => {
                    const c = range.c1 + j
                    // 行内相对引用随行移动
                    const nc = cell?.f ? { ...cell, f: shiftFormulaRowOnly(cell.f, tr - row.r, range) } : cell
                    set(tr, c, nc ?? null)
                })
            })
        }, { structural: true })
        // 行高随行移动
        const hs = rows.map(x => sh.meta.rowH.get(x.r))
        if (hs.some(x => x != null)) sh.update('rowH', m => { rows.forEach((x, i) => { const v = hs[i]; v == null ? m.delete(visibleRows[i]) : m.set(visibleRows[i], v) }) })
        this.invalidate()
    },
    quickSort(desc) {
        const { range, header } = this.sortTarget()
        this.sortRange(range, [{ c: this.sel.c, desc }], header, desc ? '降序排序' : '升序排序')
        this.selectRange(range, { active: { r: this.sel.r, c: this.sel.c } })
    },
    async sortDialog() {
        const { range, header } = this.sortTarget()
        const cols = []
        for (let c = range.c1; c <= range.c2; c++) {
            const hv = header ? this.valueOf(this.sheet, range.r1, c) : null
            cols.push([c, hv != null && hv !== '' ? `${colName(c)} 列（${hv}）` : `${colName(c)} 列`])
        }
        const v = await formDialog({
            title: '排序', width: 440,
            fields: [
                { type: 'note', label: `排序区域：${colName(range.c1)}${range.r1 + 1}:${colName(range.c2)}${range.r2 + 1}` },
                { key: 'header', label: '包含标题行', type: 'check', value: header },
                { key: 'k1', label: '主要关键字', type: 'select', value: Math.max(range.c1, Math.min(this.sel.c, range.c2)), options: cols },
                { key: 'd1', label: '次序', type: 'select', value: 'asc', options: [['asc', '升序'], ['desc', '降序']] },
                { key: 'k2', label: '次要关键字', type: 'select', value: -1, options: [[-1, '（无）'], ...cols] },
                { key: 'd2', label: '次序', type: 'select', value: 'asc', options: [['asc', '升序'], ['desc', '降序']] },
            ],
        })
        if (!v) return
        const keys = [{ c: v.k1, desc: v.d1 === 'desc' }]
        if (v.k2 >= 0) keys.push({ c: v.k2, desc: v.d2 === 'desc' })
        this.sortRange(range, keys, v.header)
        this.selectRange(range)
    },

    // ---------- 筛选 ----------
    toggleFilter() {
        const sh = this.sheet
        if (sh.meta.filter) {
            sh.setMeta({ filter: null })
            this.invalidate()
            this.commit('取消筛选')
            return
        }
        let g = this.range
        if (g.r1 === g.r2) g = this.currentRegion(g.r1, g.c1)
        else g = this.clampUsed(g)
        if (g.r2 === g.r1) g = { ...g, r2: g.r1 + 1 }
        sh.setMeta({ filter: { range: g, cols: {}, hidden: new Set() } })
        this.invalidate()
        this.commit('筛选')
    },

    // 根据条件重新计算隐藏行
    applyFilter(sh = this.sheet) {
        const f = sh.meta.filter
        if (!f) return
        const hidden = new Set()
        const conds = Object.entries(f.cols ?? {})
        // 数据区域向下扩展到连续数据末尾
        let r2 = f.range.r2
        const filled = r => { for (let c = f.range.c1; c <= f.range.c2; c++) { const x = sh.get(r, c); if (x && (x.v != null || x.f)) return true } return false }
        while (filled(r2 + 1)) r2++
        if (conds.length) {
            for (let r = f.range.r1 + 1; r <= r2; r++) {
                for (const [c, cond] of conds) {
                    const v = this.valueOf(sh, r, +c)
                    if (!matchFilter(cond, v, sh.styleAt(r, +c)?.fmt)) { hidden.add(r); break }
                }
            }
        }
        sh.setMeta({ filter: { ...f, range: { ...f.range, r2 }, hidden } })
    },
    applyFilterRefresh() {
        // 数据变化时不自动重新筛选（与 Excel 一致），只在修改条件时应用
    },

    openFilterMenu(c) {
        const sh = this.sheet, f = sh.meta.filter
        if (!f) return
        const cur = f.cols?.[c]
        // 收集唯一值
        const counts = new Map()
        let r2 = f.range.r2
        for (let r = f.range.r1 + 1; r <= r2; r++) {
            const v = this.valueOf(sh, r, c)
            const t = v == null || v === '' ? '' : display(v, sh.styleAt(r, c)?.fmt).text
            counts.set(t, (counts.get(t) ?? 0) + 1)
        }
        const values = [...counts.keys()].sort((a, b) => a === '' ? 1 : b === '' ? -1 : a.localeCompare(b, 'zh-CN', { numeric: true }))
        const checked = new Set(cur?.type === 'values' ? cur.values : values)
        const search = h('input.input.small.sh-filter-search', { placeholder: '搜索…' })
        const list = h('div.sh-filter-list')
        const render = () => {
            const q = search.value.trim().toLowerCase()
            list.replaceChildren(...values.filter(v => !q || v.toLowerCase().includes(q)).map(v => {
                const cb = h('input', { type: 'checkbox', checked: checked.has(v) })
                cb.addEventListener('change', () => { cb.checked ? checked.add(v) : checked.delete(v); allCb.checked = checked.size === values.length })
                return h('label.sh-filter-item', cb, h('span', v === '' ? '（空白）' : v), h('span.sh-filter-count', counts.get(v)))
            }))
        }
        const allCb = h('input', { type: 'checkbox', checked: checked.size === values.length })
        allCb.addEventListener('change', () => { if (allCb.checked) values.forEach(v => checked.add(v)); else checked.clear(); render() })
        search.addEventListener('input', render)
        render()
        const apply = cond => {
            const cols = { ...(f.cols ?? {}) }
            if (cond) cols[c] = cond; else delete cols[c]
            sh.setMeta({ filter: { ...f, cols } })
            this.applyFilter(sh)
            this.invalidate()
            this.commit('筛选')
        }
        const sortRange = { ...f.range }
        const panel = h('div.sh-filter-panel',
            h('div.sh-filter-values', h('label.sh-filter-item.all', allCb, h('span', '（全选）')), search, list),
            h('div.sh-filter-actions',
                h('button.btn.small', { onclick: () => { closeFn(); apply(null) } }, '清除筛选'),
                h('button.btn.small.primary', { onclick: () => { closeFn(); apply(checked.size === values.length ? null : { type: 'values', values: [...checked] }) } }, '确定')))
        const items = [
            { label: '升序', icon: 'arrow-up-a-z', run: () => { this.sortRange(sortRange, [{ c, desc: false }], true); this.commit('排序') } },
            { label: '降序', icon: 'arrow-down-z-a', run: () => { this.sortRange(sortRange, [{ c, desc: true }], true); this.commit('排序') } },
            '-',
            {
                label: '条件筛选', icon: 'filter', submenu: [
                    ['gt', '大于…'], ['lt', '小于…'], ['between', '介于…'], ['eq', '等于…'], ['ne', '不等于…'], ['contains', '包含…'], ['begins', '开头是…'],
                    ['top', '前 10 项…'], ['above', '高于平均值'], ['below', '低于平均值'],
                ].map(([op, label]) => ({ label, run: () => this.customFilter(c, op, apply) })),
            },
            cur ? { label: '清除此列筛选', icon: 'filter-x', run: () => apply(null) } : null,
            '-',
            { el: panel },
        ]
        const rc = this.grid.cellRect(f.range.r1, c)
        const box = this.grid.el.getBoundingClientRect()
        openMenu(items, { x: box.left + rc.x + rc.w - 220, y: box.top + rc.y + rc.h + 2 })
        const closeFn = () => import('../../core/menu.js').then(m => m.closeMenu())
        setTimeout(() => search.focus(), 50)
    },

    async customFilter(c, op, apply) {
        const sh = this.sheet
        if (op === 'above' || op === 'below') {
            const nums = []
            for (let r = sh.meta.filter.range.r1 + 1; r <= sh.meta.filter.range.r2; r++) { const v = this.valueOf(sh, r, c); if (typeof v === 'number') nums.push(v) }
            const avg = nums.reduce((a, b) => a + b, 0) / (nums.length || 1)
            return apply({ type: 'cond', op: op === 'above' ? 'gt' : 'lt', a: avg })
        }
        const needB = op === 'between'
        const v = await formDialog({
            title: '自定义筛选', width: 380,
            fields: [
                { key: 'a', label: op === 'top' ? '项数' : needB ? '最小值' : '值', type: op === 'contains' || op === 'begins' || op === 'eq' || op === 'ne' ? 'text' : 'number', value: op === 'top' ? 10 : '' },
                needB ? { key: 'b', label: '最大值', type: 'number', value: '' } : null,
            ].filter(Boolean),
        })
        if (!v) return
        if (op === 'top') {
            const nums = []
            for (let r = sh.meta.filter.range.r1 + 1; r <= sh.meta.filter.range.r2; r++) { const x = this.valueOf(sh, r, c); if (typeof x === 'number') nums.push(x) }
            nums.sort((a, b) => b - a)
            return apply({ type: 'cond', op: 'ge', a: nums[Math.min(nums.length, Math.max(1, +v.a)) - 1] ?? 0 })
        }
        apply({ type: 'cond', op, a: v.a, b: v.b })
    },

    reapplyFilter() {
        if (!this.sheet.meta.filter) return
        this.applyFilter()
        this.invalidate()
        this.commit('重新应用筛选')
    },

    // ---------- 查找与替换 ----------
    findDialog(replace = false) {
        const st = this.findState ??= { q: '', rep: '', matchCase: false, whole: false, formulas: false, allSheets: false }
        const q = h('input.input.small', { value: st.q, placeholder: '查找内容' })
        const rep = h('input.input.small', { value: st.rep, placeholder: '替换为' })
        const opt = (key, label) => {
            const cb = h('input', { type: 'checkbox', checked: st[key] })
            cb.addEventListener('change', () => { st[key] = cb.checked })
            return h('label.sh-check', cb, label)
        }
        const info = h('div.form-note', ' ')
        const sync = () => { st.q = q.value; st.rep = rep.value }
        const find = dir => {
            sync()
            const res = this.findNext(st, dir)
            info.textContent = res ? `找到：${res.sheet.name}!${colName(res.c)}${res.r + 1}` : '找不到匹配的内容'
        }
        const body = h('div.form',
            h('label.form-row', h('span.form-label', '查找'), q),
            h('label.form-row' + (replace ? '' : '.hidden-row'), { hidden: !replace }, h('span.form-label', '替换为'), rep),
            h('div.sh-find-opts', opt('matchCase', '区分大小写'), opt('whole', '单元格完全匹配'), opt('formulas', '查找公式'), opt('allSheets', '所有工作表')),
            info,
            h('div.sh-find-btns',
                h('button.btn.small', { onclick: () => find(-1) }, icon('chevron-up', 15), '上一个'),
                h('button.btn.small', { onclick: () => find(1) }, icon('chevron-down', 15), '下一个'),
                replace ? h('button.btn.small', { onclick: () => { sync(); const n = this.replaceOne(st); info.textContent = n ? '已替换 1 处' : '找不到匹配的内容' } }, '替换') : null,
                replace ? h('button.btn.small.primary', { onclick: () => { sync(); const n = this.replaceAll(st); info.textContent = `已替换 ${n} 处` } }, '全部替换') : null))
        q.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); e.stopPropagation(); find(e.shiftKey ? -1 : 1) } })
        dialog({ title: replace ? '查找和替换' : '查找', body, width: 460, actions: [{ label: '关闭', value: null }] }).then(() => this.focusGrid())
    },

    matcher(st) {
        const flags = st.matchCase ? '' : 'i'
        const esc = st.q.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.')
        return new RegExp(st.whole ? '^' + esc + '$' : esc, flags + 'g')
    },
    cellSearchText(sh, r, c, cell, st) {
        if (st.formulas && cell.f) return '=' + cell.f
        const v = this.valueOf(sh, r, c, cell)
        return display(v, sh.styleAt(r, c, cell)?.fmt).text
    },
    findNext(st, dir = 1) {
        if (!st.q) return null
        const re = this.matcher(st)
        const sheets = st.allSheets ? [...this.sheets.slice(this.book.active), ...this.sheets.slice(0, this.book.active)] : [this.sheet]
        if (dir < 0) sheets.reverse()
        const cur = { r: this.sel.r, c: this.sel.c }
        for (let pass = 0; pass < 2; pass++) {
            for (const sh of sheets) {
                const list = sh.cells.sorted()
                if (dir < 0) list.reverse()
                for (const [r, c, cell] of list) {
                    if (sh === this.sheet && pass === 0) {
                        const after = dir > 0 ? (r > cur.r || (r === cur.r && c > cur.c)) : (r < cur.r || (r === cur.r && c < cur.c))
                        if (!after) continue
                    }
                    re.lastIndex = 0
                    if (re.test(this.cellSearchText(sh, r, c, cell, st))) {
                        if (sh !== this.sheet) this.switchSheet(this.sheets.indexOf(sh))
                        this.selectCell(r, c)
                        return { sheet: sh, r, c }
                    }
                }
            }
        }
        return null
    },
    replaceIn(sh, r, c, cell, st) {
        const re = this.matcher(st)
        const src = cell.f ? '=' + cell.f : cell.v == null ? '' : String(cell.v)
        const out = src.replace(re, st.rep)
        if (out === src) return false
        this.setInput(r, c, out, sh, { commit: false })
        return true
    },
    replaceOne(st) {
        const sh = this.sheet
        const cell = sh.get(this.sel.r, this.sel.c)
        if (cell && this.replaceIn(sh, this.sel.r, this.sel.c, cell, { ...st, formulas: true })) { this.commit('替换'); this.findNext(st, 1); return 1 }
        return this.findNext(st, 1) ? 0 : 0
    },
    replaceAll(st) {
        if (!st.q) return 0
        let n = 0
        for (const sh of st.allSheets ? this.sheets : [this.sheet]) {
            for (const [r, c, cell] of sh.cells.sorted()) {
                const re = this.matcher(st)
                if (!re.test(this.cellSearchText(sh, r, c, cell, st)) && !(cell.f && re.test('=' + cell.f))) continue
                if (this.replaceIn(sh, r, c, cell, { ...st, formulas: true })) n++
            }
        }
        if (n) this.commit('全部替换')
        return n
    },

    // ---------- 删除重复项 ----------
    async removeDuplicates() {
        const { range, header } = this.sortTarget()
        const cols = []
        for (let c = range.c1; c <= range.c2; c++) cols.push({ key: 'c' + c, label: `${colName(c)} 列`, type: 'check', value: true })
        const v = await formDialog({ title: '删除重复项', fields: [{ key: 'header', label: '数据包含标题', type: 'check', value: header }, { type: 'note', label: '依据以下列判断重复：' }, ...cols] })
        if (!v) return
        const keyCols = []
        for (let c = range.c1; c <= range.c2; c++) if (v['c' + c]) keyCols.push(c)
        if (!keyCols.length) return
        const sh = this.sheet
        const seen = new Set()
        const keep = []
        const r0 = range.r1 + (v.header ? 1 : 0)
        for (let r = r0; r <= range.r2; r++) {
            const key = JSON.stringify(keyCols.map(c => { const x = this.valueOf(sh, r, c); return typeof x === 'string' ? x.toLowerCase() : x }))
            if (seen.has(key)) continue
            seen.add(key)
            keep.push(r)
        }
        const removed = range.r2 - r0 + 1 - keep.length
        this.batch('删除重复项', set => {
            const rows = keep.map(r => { const a = []; for (let c = range.c1; c <= range.c2; c++) a.push(sh.get(r, c)); return a })
            for (let r = r0; r <= range.r2; r++) for (let c = range.c1; c <= range.c2; c++) set(r, c, null)
            rows.forEach((a, i) => a.forEach((cell, j) => set(r0 + i, range.c1 + j, cell ?? null)))
        }, { structural: true })
        toast(`已删除 ${removed} 个重复项，保留 ${keep.length} 个唯一值`, 'success')
    },

    // ---------- 数据验证 ----------
    async validationDialog() {
        const g = this.clampUsedForWrite(this.range)
        const cur = this.validationAt(this.sel.r, this.sel.c)
        const v = await formDialog({
            title: '数据验证', width: 440,
            fields: [
                { key: 'type', label: '允许', type: 'select', value: cur?.type ?? 'list', options: [['list', '序列（下拉列表）'], ['number', '小数'], ['integer', '整数'], ['length', '文本长度'], ['none', '任何值（清除验证）']] },
                { key: 'source', label: '来源', type: 'text', value: cur?.source ?? '', placeholder: '选项1,选项2 或 =$A$1:$A$5' },
                { key: 'min', label: '最小值', type: 'text', value: cur?.min ?? '' },
                { key: 'max', label: '最大值', type: 'text', value: cur?.max ?? '' },
                { key: 'message', label: '出错提示', type: 'text', value: cur?.message ?? '' },
            ],
        })
        if (!v) return
        const sh = this.sheet
        const rest = sh.meta.validations.filter(x => !(x.range.r1 >= g.r1 && x.range.r2 <= g.r2 && x.range.c1 >= g.c1 && x.range.c2 <= g.c2) && !inRange(x.range, this.sel.r, this.sel.c))
        if (v.type !== 'none') rest.push({ range: g, type: v.type, source: v.source, min: v.min, max: v.max, message: v.message })
        sh.setMeta({ validations: rest })
        this.invalidate()
        this.commit('数据验证')
    },
    openValidationList() {
        const dv = this.validationAt(this.sel.r, this.sel.c)
        if (!dv) return
        const items = this.listItems(dv)
        const b = this.grid.dvButton
        const box = this.grid.el.getBoundingClientRect()
        const a = this.activeRect()
        openMenu(items.map(x => ({ label: String(x), run: () => this.setInput(this.sel.r, this.sel.c, String(x)) })), { x: box.left + a.x, y: box.top + a.y + a.h + 2 })
        void b
    },
}

function matchFilter(cond, v, fmt) {
    if (cond.type === 'values') {
        const t = v == null || v === '' ? '' : display(v, fmt).text
        return cond.values.includes(t)
    }
    const n = typeof v === 'number' ? v : null
    const a = cond.a, b = cond.b
    const s = v == null ? '' : String(v).toLowerCase()
    switch (cond.op) {
        case 'gt': return n != null && n > +a
        case 'lt': return n != null && n < +a
        case 'ge': return n != null && n >= +a
        case 'between': return n != null && n >= Math.min(+a, +b) && n <= Math.max(+a, +b)
        case 'eq': return n != null && a !== '' && !isNaN(+a) ? n === +a : s === String(a).toLowerCase()
        case 'ne': return n != null && a !== '' && !isNaN(+a) ? n !== +a : s !== String(a).toLowerCase()
        case 'contains': return s.includes(String(a).toLowerCase())
        case 'begins': return s.startsWith(String(a).toLowerCase())
    }
    return true
}

// 排序时公式随行移动：只平移指向排序区域内同一行的相对行引用（简化：整体按行偏移平移相对引用）
function shiftFormulaRowOnly(f, dr) {
    return shiftFormula(f, dr, 0)
}
