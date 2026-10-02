// 电子表格菜单：菜单栏、单元格 / 行 / 列右键菜单、条件格式菜单
import { CF_PRESETS } from './format.js'
import { CHART_KINDS } from './chart.js'

export const Menus = {
    menus() {
        const hasSel = () => true
        return [
            {
                label: '编辑', items: () => [
                    ...this.undoItems(), '-',
                    { label: '剪切', icon: 'scissors', key: 'Ctrl+X', run: () => this.copy(true) },
                    { label: '复制', icon: 'copy', key: 'Ctrl+C', run: () => this.copy(false) },
                    { label: '粘贴', icon: 'clipboard-paste', key: 'Ctrl+V', run: () => this.paste('all') },
                    { label: '选择性粘贴', icon: 'clipboard-list', submenu: this.pasteSpecialItems() },
                    '-',
                    { label: '填充', icon: 'arrow-down-to-line', submenu: [
                        { label: '向下填充', key: 'Ctrl+D', run: () => this.fillDir('down') },
                        { label: '向右填充', key: 'Ctrl+R', run: () => this.fillDir('right') },
                        { label: '向上填充', run: () => this.fillDir('up') },
                        { label: '向左填充', run: () => this.fillDir('left') },
                    ] },
                    { label: '清除', icon: 'eraser', submenu: [
                        { label: '清除内容', key: 'Delete', run: () => this.clearContents() },
                        { label: '清除格式', run: () => this.clearAll('format') },
                        { label: '全部清除', run: () => this.clearAll('all') },
                    ] },
                    '-',
                    { label: '全选', key: 'Ctrl+A', run: () => this.selectAll() },
                    { label: '查找…', icon: 'search', key: 'Ctrl+F', run: () => this.findDialog(false) },
                    { label: '替换…', icon: 'replace', key: 'Ctrl+H', run: () => this.findDialog(true) },
                    { label: '定位…', icon: 'crosshair', key: 'Ctrl+G', run: () => { this.nameBox.focus(); this.nameBox.select() } },
                ],
            },
            {
                label: '视图', items: () => [
                    { label: '编辑栏', checked: () => !this.fxBar.hidden, run: () => { this.fxBar.hidden = !this.fxBar.hidden; this.grid.layout() } },
                    { label: '网格线', checked: () => this.sheet.meta.showGrid !== false, run: () => this.toggleGridlines() },
                    '-',
                    { label: '冻结窗格', icon: 'snowflake', submenu: () => this.freezeItems() },
                    '-',
                    { label: '放大', icon: 'zoom-in', key: 'Ctrl+=', run: () => this.setZoom(this.zoom + 0.1) },
                    { label: '缩小', icon: 'zoom-out', key: 'Ctrl+-', run: () => this.setZoom(this.zoom - 0.1) },
                    { label: '100%', key: 'Ctrl+0', run: () => this.setZoom(1) },
                ],
            },
            {
                label: '插入', items: () => [
                    { label: '行', submenu: [{ label: '在上方插入行', run: () => this.insertRows('above') }, { label: '在下方插入行', run: () => this.insertRows('below') }] },
                    { label: '列', submenu: [{ label: '在左侧插入列', run: () => this.insertCols('left') }, { label: '在右侧插入列', run: () => this.insertCols('right') }] },
                    { label: '单元格…', submenu: [{ label: '活动单元格右移', run: () => this.shiftCells('insert-right') }, { label: '活动单元格下移', run: () => this.shiftCells('insert-down') }] },
                    { label: '工作表', icon: 'plus', key: 'Shift+F11', run: () => this.addSheet() },
                    '-',
                    { label: '图表', icon: 'chart-column', submenu: CHART_KINDS.map(([k, l]) => ({ label: l, run: () => this.insertChart(k) })) },
                    { label: '函数…', icon: 'square-function', key: 'Shift+F3', run: () => this.insertFunctionDialog() },
                    '-',
                    { label: '当前日期', key: 'Ctrl+;', run: () => this.onKey({ target: this.input, key: ';', ctrlKey: true, code: 'Semicolon' }) },
                ],
            },
            {
                label: '格式', items: () => [
                    { label: '设置单元格格式…', icon: 'settings-2', key: 'Ctrl+1', run: () => this.formatCellsDialog() },
                    '-',
                    { label: '加粗', icon: 'bold', key: 'Ctrl+B', run: () => this.toggleStyle('b') },
                    { label: '倾斜', icon: 'italic', key: 'Ctrl+I', run: () => this.toggleStyle('i') },
                    { label: '下划线', icon: 'underline', key: 'Ctrl+U', run: () => this.toggleStyle('u') },
                    { label: '删除线', icon: 'strikethrough', key: 'Ctrl+5', run: () => this.toggleStyle('st') },
                    '-',
                    { label: '数字格式', submenu: () => this.numFmtItems() },
                    { label: '边框', icon: 'grid-2x2', submenu: () => this.borderItems() },
                    { label: '合并单元格', icon: 'table-cells-merge', submenu: [
                        { label: '合并后居中', run: () => this.mergeCells('center') }, { label: '跨越合并', run: () => this.mergeCells('across') },
                        { label: '合并单元格', run: () => this.mergeCells('merge') }, { label: '取消合并', run: () => this.mergeCells('unmerge') },
                    ] },
                    { label: '条件格式', icon: 'paintbrush-vertical', submenu: () => this.cfMenuItems() },
                    '-',
                    { label: '行高…', run: () => this.sizeDialog('row') },
                    { label: '列宽…', run: () => this.sizeDialog('col') },
                    { label: '自动调整列宽', run: () => this.autoFitCols([this.range.c1, this.range.c2]) },
                    { label: '自动调整行高', run: () => this.autoFitRows([this.range.r1, this.range.r2]) },
                    '-',
                    { label: '格式刷', icon: 'paintbrush', run: () => this.startPainter(false) },
                    { label: '清除格式', icon: 'remove-formatting', run: () => this.clearAll('format') },
                ],
            },
            {
                label: '公式', items: () => [
                    { label: '插入函数…', icon: 'square-function', key: 'Shift+F3', run: () => this.insertFunctionDialog() },
                    { label: '自动求和', icon: 'sigma', submenu: () => this.autoSumItems() },
                    '-',
                    ...[['数学与三角', 'math'], ['统计', 'stat'], ['逻辑', 'logic'], ['文本', 'text'], ['查找与引用', 'lookup'], ['日期与时间', 'date']].map(([l, cat]) => ({
                        label: l, submenu: () => this.funcCategory(cat).map(n => ({ label: n, run: () => this.startEdit({ mode: 'enter', text: `=${n}(` }) })),
                    })),
                    '-',
                    { label: '显示公式', key: 'Ctrl+`', checked: () => !!this.showFormulas, run: () => { this.showFormulas = !this.showFormulas; this.grid.requestDraw() } },
                    { label: '重新计算', icon: 'refresh-cw', key: 'F9', run: () => { this.engine.rebuild(); this.invalidate(); } },
                ],
            },
            {
                label: '数据', items: () => [
                    { label: '升序排序', icon: 'arrow-down-a-z', run: () => this.quickSort(false) },
                    { label: '降序排序', icon: 'arrow-down-z-a', run: () => this.quickSort(true) },
                    { label: '自定义排序…', icon: 'arrow-up-down', run: () => this.sortDialog() },
                    '-',
                    { label: '筛选', icon: 'filter', key: 'Ctrl+Shift+L', checked: () => !!this.sheet.meta.filter, run: () => this.toggleFilter() },
                    { label: '重新应用筛选', disabled: () => !this.sheet.meta.filter, run: () => this.reapplyFilter() },
                    '-',
                    { label: '删除重复项…', icon: 'copy-minus', run: () => this.removeDuplicates() },
                    { label: '分列…', icon: 'columns-3', run: () => this.textToColumns() },
                    { label: '数据验证…', icon: 'shield-check', run: () => this.validationDialog() },
                ],
            },
            {
                label: '工作表', items: () => [
                    { label: '新建工作表', icon: 'plus', run: () => this.addSheet() },
                    { label: '重命名…', icon: 'pencil', run: () => this.renameSheet() },
                    { label: '创建副本', icon: 'copy', run: () => this.duplicateSheet() },
                    { label: '删除工作表', icon: 'trash-2', danger: true, disabled: () => this.sheets.length <= 1, run: () => this.deleteSheet() },
                    '-',
                    { label: '隐藏行', run: () => this.hideRowsCols('row', true) },
                    { label: '取消隐藏行', run: () => this.hideRowsCols('row', false) },
                    { label: '隐藏列', run: () => this.hideRowsCols('col', true) },
                    { label: '取消隐藏列', run: () => this.hideRowsCols('col', false) },
                ],
            },
        ].map(m => ({ ...m, hasSel }))
    },

    pasteSpecialItems() {
        return [
            { label: '仅粘贴值', key: 'Ctrl+Shift+V', run: () => this.paste('values') },
            { label: '仅粘贴格式', run: () => this.paste('formats') },
            { label: '仅粘贴公式', run: () => this.paste('formulas') },
            { label: '转置', run: () => this.paste('transpose') },
        ]
    },

    numFmtItems() {
        return [
            ['General', '常规'], ['0.00', '数值'], ['#,##0.00', '千分位'], ['"¥"#,##0.00', '货币'], ['0.00%', '百分比'],
            ['yyyy-mm-dd', '日期'], ['yyyy"年"m"月"d"日"', '长日期'], ['h:mm:ss', '时间'], ['0.00E+00', '科学计数'], ['@', '文本'],
        ].map(([f, l]) => ({ label: l, checked: () => (this.curStyle()?.fmt ?? 'General') === f, run: () => this.applyStyle({ fmt: f === 'General' ? null : f }, '数字格式') }))
    },

    cellMenu() {
        const chart = this.selChart ? this.chartMenu(this.selChart) : null
        if (chart) return chart
        return [
            { label: '剪切', icon: 'scissors', key: 'Ctrl+X', run: () => this.copy(true) },
            { label: '复制', icon: 'copy', key: 'Ctrl+C', run: () => this.copy(false) },
            { label: '粘贴', icon: 'clipboard-paste', key: 'Ctrl+V', run: () => this.paste('all') },
            { label: '选择性粘贴', icon: 'clipboard-list', submenu: this.pasteSpecialItems() },
            '-',
            { label: '插入', icon: 'plus', submenu: [
                { label: '在上方插入行', run: () => this.insertRows('above') }, { label: '在下方插入行', run: () => this.insertRows('below') },
                { label: '在左侧插入列', run: () => this.insertCols('left') }, { label: '在右侧插入列', run: () => this.insertCols('right') },
                '-',
                { label: '插入单元格，现有单元格右移', run: () => this.shiftCells('insert-right') }, { label: '插入单元格，现有单元格下移', run: () => this.shiftCells('insert-down') },
            ] },
            { label: '删除', icon: 'minus', submenu: [
                { label: '删除行', run: () => this.deleteRows() }, { label: '删除列', run: () => this.deleteCols() },
                '-',
                { label: '删除单元格，右侧单元格左移', run: () => this.shiftCells('delete-left') }, { label: '删除单元格，下方单元格上移', run: () => this.shiftCells('delete-up') },
            ] },
            { label: '清除内容', icon: 'eraser', key: 'Delete', run: () => this.clearContents() },
            '-',
            { label: '排序', icon: 'arrow-down-a-z', submenu: [{ label: '升序', run: () => this.quickSort(false) }, { label: '降序', run: () => this.quickSort(true) }, { label: '自定义排序…', run: () => this.sortDialog() }] },
            { label: '筛选', icon: 'filter', run: () => this.toggleFilter() },
            { label: '插入图表', icon: 'chart-column', submenu: CHART_KINDS.map(([k, l]) => ({ label: l, run: () => this.insertChart(k) })) },
            '-',
            { label: '设置单元格格式…', icon: 'settings-2', key: 'Ctrl+1', run: () => this.formatCellsDialog() },
            { label: '条件格式', icon: 'paintbrush-vertical', submenu: () => this.cfMenuItems() },
            { label: '数据验证…', icon: 'shield-check', run: () => this.validationDialog() },
        ]
    },
    rowMenu() {
        const n = this.range.r2 - this.range.r1 + 1
        return [
            { label: '剪切', icon: 'scissors', run: () => this.copy(true) },
            { label: '复制', icon: 'copy', run: () => this.copy(false) },
            { label: '粘贴', icon: 'clipboard-paste', run: () => this.paste('all') },
            '-',
            { label: `在上方插入 ${n} 行`, icon: 'arrow-up-to-line', run: () => this.insertRows('above') },
            { label: `在下方插入 ${n} 行`, icon: 'arrow-down-to-line', run: () => this.insertRows('below') },
            { label: '删除行', icon: 'trash-2', danger: true, run: () => this.deleteRows() },
            { label: '清除内容', icon: 'eraser', run: () => this.clearContents() },
            '-',
            { label: '行高…', run: () => this.sizeDialog('row') },
            { label: '自动调整行高', run: () => this.autoFitRows([this.range.r1, this.range.r2]) },
            { label: '隐藏', icon: 'eye-off', run: () => this.hideRowsCols('row', true) },
            { label: '取消隐藏', icon: 'eye', run: () => this.hideRowsCols('row', false) },
            { label: '冻结至此行', icon: 'snowflake', run: () => this.setFreeze(this.range.r2 + 1, this.sheet.meta.freeze.c) },
        ]
    },
    colMenu() {
        const n = this.range.c2 - this.range.c1 + 1
        return [
            { label: '剪切', icon: 'scissors', run: () => this.copy(true) },
            { label: '复制', icon: 'copy', run: () => this.copy(false) },
            { label: '粘贴', icon: 'clipboard-paste', run: () => this.paste('all') },
            '-',
            { label: `在左侧插入 ${n} 列`, icon: 'arrow-left-to-line', run: () => this.insertCols('left') },
            { label: `在右侧插入 ${n} 列`, icon: 'arrow-right-to-line', run: () => this.insertCols('right') },
            { label: '删除列', icon: 'trash-2', danger: true, run: () => this.deleteCols() },
            { label: '清除内容', icon: 'eraser', run: () => this.clearContents() },
            '-',
            { label: '升序排序', icon: 'arrow-down-a-z', run: () => this.quickSort(false) },
            { label: '降序排序', icon: 'arrow-down-z-a', run: () => this.quickSort(true) },
            '-',
            { label: '列宽…', run: () => this.sizeDialog('col') },
            { label: '自动调整列宽', run: () => this.autoFitCols([this.range.c1, this.range.c2]) },
            { label: '隐藏', icon: 'eye-off', run: () => this.hideRowsCols('col', true) },
            { label: '取消隐藏', icon: 'eye', run: () => this.hideRowsCols('col', false) },
            { label: '冻结至此列', icon: 'snowflake', run: () => this.setFreeze(this.sheet.meta.freeze.r, this.range.c2 + 1) },
        ]
    },

    cfMenuItems() {
        const quick = (type, label, a) => ({ label, run: () => this.cfDialog(type, a) })
        return [
            { header: '突出显示单元格规则' },
            quick('gt', '大于…'), quick('lt', '小于…'), quick('between', '介于…'), quick('eq', '等于…'), quick('text', '文本包含…'), quick('dup', '重复值…'),
            '-',
            { header: '最前 / 最后规则' },
            quick('top', '值最大的 10 项…', 10), quick('bottom', '值最小的 10 项…', 10), quick('above', '高于平均值…'), quick('below', '低于平均值…'),
            '-',
            { label: '数据条', icon: 'chart-bar', submenu: ['#638ec6', '#63be7b', '#ff555a', '#ffb628', '#008aef', '#d6007b'].map(c => ({ label: c, swatch: c, run: () => this.addCF({ type: 'bar', color: c }, '数据条') })) },
            { label: '色阶', icon: 'palette', submenu: [
                { label: '红-黄-绿', run: () => this.addCF({ type: 'scale', colors: ['#f8696b', '#ffeb84', '#63be7b'] }, '色阶') },
                { label: '绿-黄-红', run: () => this.addCF({ type: 'scale', colors: ['#63be7b', '#ffeb84', '#f8696b'] }, '色阶') },
                { label: '白-红', run: () => this.addCF({ type: 'scale', colors: ['#ffffff', '#f8696b'] }, '色阶') },
                { label: '白-绿', run: () => this.addCF({ type: 'scale', colors: ['#ffffff', '#63be7b'] }, '色阶') },
                { label: '蓝-白-红', run: () => this.addCF({ type: 'scale', colors: ['#5a8ac6', '#fcfcff', '#f8696b'] }, '色阶') },
            ] },
            '-',
            { label: '新建规则…', icon: 'plus', run: () => this.cfDialog('formula') },
            { label: '管理规则…', icon: 'list', disabled: () => !this.sheet.meta.cf.length, run: () => this.cfManager() },
            { label: '清除所选区域的规则', icon: 'eraser', run: () => this.clearCF(false) },
            { label: '清除整个工作表的规则', run: () => this.clearCF(true) },
        ]
    },

    addCF(rule, label = '条件格式') {
        const range = this.clampUsed(this.range)
        const id = Math.random().toString(36).slice(2, 9)
        this.sheet.setMeta({ cf: [...this.sheet.meta.cf, { id, range, ...rule, style: rule.style ?? CF_PRESETS[0][1] }] })
        this.cfCache.clear()
        this.invalidate()
        this.commit(label)
    },
    clearCF(all) {
        const g = this.range
        const cf = all ? [] : this.sheet.meta.cf.filter(r => !(r.range.r1 <= g.r2 && r.range.r2 >= g.r1 && r.range.c1 <= g.c2 && r.range.c2 >= g.c1))
        this.sheet.setMeta({ cf })
        this.cfCache.clear()
        this.invalidate()
        this.commit('清除条件格式')
    },

    funcCategory(cat) {
        const C = {
            math: ['SUM', 'SUMIF', 'SUMIFS', 'SUMPRODUCT', 'ROUND', 'ROUNDUP', 'ROUNDDOWN', 'INT', 'ABS', 'SQRT', 'POWER', 'MOD', 'PI', 'RAND', 'RANDBETWEEN', 'PRODUCT', 'CEILING', 'FLOOR', 'EXP', 'LN', 'LOG10', 'SIN', 'COS', 'TAN'],
            stat: ['AVERAGE', 'AVERAGEIF', 'AVERAGEIFS', 'COUNT', 'COUNTA', 'COUNTBLANK', 'COUNTIF', 'COUNTIFS', 'MAX', 'MIN', 'MEDIAN', 'MODE', 'STDEV', 'VAR', 'RANK', 'LARGE', 'SMALL', 'MAXIFS', 'MINIFS'],
            logic: ['IF', 'IFS', 'IFERROR', 'IFNA', 'AND', 'OR', 'NOT', 'XOR', 'SWITCH', 'TRUE', 'FALSE'],
            text: ['CONCAT', 'CONCATENATE', 'TEXTJOIN', 'LEFT', 'RIGHT', 'MID', 'LEN', 'UPPER', 'LOWER', 'PROPER', 'TRIM', 'TEXT', 'VALUE', 'FIND', 'SEARCH', 'SUBSTITUTE', 'REPLACE', 'REPT', 'EXACT'],
            lookup: ['VLOOKUP', 'HLOOKUP', 'XLOOKUP', 'INDEX', 'MATCH', 'CHOOSE', 'ROW', 'COLUMN', 'ROWS', 'COLUMNS', 'INDIRECT', 'OFFSET'],
            date: ['TODAY', 'NOW', 'DATE', 'YEAR', 'MONTH', 'DAY', 'HOUR', 'MINUTE', 'SECOND', 'WEEKDAY', 'DATEDIF', 'EDATE', 'EOMONTH', 'NETWORKDAYS', 'WORKDAY'],
        }
        return (C[cat] ?? []).filter(n => this.funcExists(n))
    },
}
