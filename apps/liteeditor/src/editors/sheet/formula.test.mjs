// 公式引擎单元测试：node src/editors/sheet/formula.test.mjs
import { Engine } from './formula/engine.js'
import { Sheet, makeCell } from './model.js'
import { parseCell } from './addr.js'
import { shiftFormula, adjustFormula, renameSheetInFormula } from './formula/lexer.js'
import { formatValue } from './numfmt.js'
import { isErr } from './formula/values.js'

let pass = 0, fail = 0
const eq = (a, b, msg) => {
    const ok = Object.is(a, b) || (typeof a === 'number' && typeof b === 'number' && Math.abs(a - b) < 1e-9) || String(a) === String(b) && (isErr(a) || isErr(b))
    if (ok) pass++
    else { fail++; console.log('✗', msg, '→', a, '期望', b) }
}

const s1 = new Sheet('Sheet1'), s2 = new Sheet('数据')
const book = { sheets: [s1, s2] }
const eng = new Engine(book)
const set = (sh, a, v) => {
    const { r, c } = parseCell(a)
    const cell = typeof v === 'string' && v.startsWith('=') ? makeCell(null, v.slice(1)) : makeCell(v)
    sh.set(r, c, cell)
    return [sh.id, r, c]
}
const put = (a, v, sh = s1) => eng.changed([set(sh, a, v)])
const val = (a, sh = s1) => { const { r, c } = parseCell(a); return eng.value(sh.id, r, c) }
const f = (src, expect) => { put('Z100', '=' + src); eq(val('Z100'), expect, src) }

// 数据
const data = [[1, 'a', 10], [2, 'b', 20], [3, 'c', 30], [4, 'b', 40], [5, 'e', 50]]
data.forEach((row, i) => row.forEach((v, j) => set(s1, String.fromCharCode(65 + j) + (i + 1), v)))
set(s2, 'A1', 100)
eng.rebuild()

f('1+2*3', 7); f('(1+2)*3', 9); f('2^3^2', 64); f('-2^2', 4); f('10%', 0.1); f('50%*4', 2)
f('"a"&"b"&1', 'ab1'); f('1=1', true); f('"A"="a"', true); f('2<>2', false); f('3>=3', true); f('"b">"a"', true)
f('1/0', '#DIV/0!'); f('"x"+1', '#VALUE!'); f('FOO(1)', '#NAME?'); f('"3"+4', 7)
f('SUM(A1:A5)', 15); f('SUM(A:A)', 15); f('AVERAGE(C1:C5)', 30); f('MIN(C1:C5)', 10); f('MAX(A1:C5)', 50)
f('COUNT(A1:C5)', 10); f('COUNTA(A1:C5)', 15); f('COUNTIF(B1:B5,"b")', 2); f('COUNTIF(C1:C5,">25")', 3)
f('SUMIF(B1:B5,"b",C1:C5)', 60); f('AVERAGEIF(A1:A5,">2",C1:C5)', 40); f('SUMIFS(C1:C5,A1:A5,">1",B1:B5,"b")', 60)
f('IF(A1>0,"正","负")', '正'); f('IFS(A3=1,"x",A3=3,"y")', 'y'); f('AND(TRUE,1>0)', true); f('OR(FALSE,0)', false); f('NOT(TRUE)', false)
f('IFERROR(1/0,"错")', '错'); f('ROUND(2.345,2)', 2.35); f('ROUND(-2.5,0)', -3); f('ROUNDUP(2.301,1)', 2.4); f('ROUNDDOWN(-2.39,1)', -2.3)
f('ABS(-3)', 3); f('SQRT(16)', 4); f('POWER(2,10)', 1024); f('MOD(-3,2)', 1); f('INT(-2.5)', -3); f('ROUND(PI(),4)', 3.1416)
f('LEN("你好ab")', 4); f('LEFT("abcdef",2)', 'ab'); f('RIGHT("abcdef",3)', 'def'); f('MID("abcdef",2,3)', 'bcd')
f('UPPER("ab")', 'AB'); f('LOWER("AB")', 'ab'); f('TRIM("  a   b ")', 'a b'); f('CONCAT(B1:B3,"!")', 'abc!'); f('CONCATENATE("a",1,TRUE)', 'a1TRUE')
f('TEXT(0.256,"0.0%")', '25.6%'); f('TEXT(1234.5,"#,##0.00")', '1,234.50'); f('VALUE("1,234")', 1234); f('FIND("c","abcabc",4)', 6)
f('SUBSTITUTE("a-b-c","-","+")', 'a+b+c'); f('SUBSTITUTE("a-b-c","-","+",2)', 'a-b+c')
f('VLOOKUP(3,A1:C5,3,FALSE)', 30); f('VLOOKUP(3.5,A1:C5,2)', 'c'); f('VLOOKUP(9,A1:C5,2,FALSE)', '#N/A')
f('HLOOKUP(1,A1:C3,3,FALSE)', 3); f('XLOOKUP("e",B1:B5,C1:C5)', 50); f('XLOOKUP("z",B1:B5,C1:C5,"无")', '无')
f('INDEX(A1:C5,2,3)', 20); f('MATCH("c",B1:B5,0)', 3); f('INDEX(C1:C5,MATCH(4,A1:A5,0))', 40)
f('YEAR(DATE(2024,3,15))', 2024); f('MONTH(DATE(2024,3,15))', 3); f('DAY(DATE(2024,2,30))', 1); f('DATE(2024,1,1)', 45292)
f('RANK(30,C1:C5)', 3); f('RANK(30,C1:C5,1)', 3); f('RANK(50,C1:C5)', 1); f('MEDIAN(1,3,2,4)', 2.5); f('ROUND(STDEV(C1:C5),6)', 15.811388)
f('SUMPRODUCT(A1:A5,C1:C5)', 550); f('SUM(数据!A1,1)', 101); f("'数据'!A1*2", 200); f('SUM(A1:A5*2)', 30)
f('YEAR(TODAY())>2020', true); f('NOW()>TODAY()-1', true); f('RANDBETWEEN(1,1)', 1); f('RAND()<1', true)
f('SUM({1,2;3,4})', 10); f('Nope!A1', '#REF!'); f('IF(1,,2)', 0)

// 依赖重算
put('D1', '=A1*2'); put('D2', '=D1+SUM(A1:A5)'); eq(val('D2'), 17, '链式')
put('A1', 11); eq(val('D1'), 22, '增量重算 D1'); eq(val('D2'), 47, '增量重算 D2 (区域依赖)')
put('A1', 1)
// 跨表依赖
put('E1', '=数据!A1+1'); put('A1', 5, s2); eq(val('E1'), 6, '跨表增量')
// 循环
put('F1', '=F2+1'); put('F2', '=F1+1'); eq(String(val('F1')), '#CIRC!', '循环 F1'); eq(String(val('F2')), '#CIRC!', '循环 F2')
put('F2', 5); eq(val('F1'), 6, '解除循环')
put('G1', '=G1'); eq(String(val('G1')), '#CIRC!', '自引用')
// 深链
for (let i = 1; i <= 3000; i++) set(s1, 'H' + i, i === 1 ? 1 : `=H${i - 1}+1`)
eng.rebuild(); eq(val('H3000'), 3000, '深依赖链')
put('H1', 10); eq(val('H3000'), 3009, '深依赖链增量')

// 引用变换
eq(shiftFormula('A1+$B$2+B$3+$C4', 1, 1), 'B2+$B$2+C$3+$C5', '相对引用平移')
eq(shiftFormula('SUM(A1:B2)', -1, 0), 'SUM(#REF!)', '越界')
eq(shiftFormula('数据!A1', 2, 0), '数据!A3', '跨表平移')
eq(adjustFormula('SUM(A1:A10)+B5', { axis: 'row', at: 2, count: 2, targetSheet: 'S', formulaSheet: 'S' }), 'SUM(A1:A12)+B7', '插入行')
eq(adjustFormula('SUM(A1:A10)+B5', { axis: 'row', at: 4, count: -1, targetSheet: 'S', formulaSheet: 'S' }), 'SUM(A1:A9)+#REF!', '删除行')
eq(adjustFormula('C1+A1', { axis: 'col', at: 1, count: 1, targetSheet: 'S', formulaSheet: 'S' }), 'D1+A1', '插入列')
eq(adjustFormula('X!A5+A5', { axis: 'row', at: 0, count: 1, targetSheet: 'X', formulaSheet: 'S' }), 'X!A6+A5', '跨表插入行')
eq(renameSheetInFormula("数据!A1+'数据'!B2", '数据', 'My Data'), "'My Data'!A1+'My Data'!B2", '重命名工作表')

// 数字格式
const fv = (v, fmt) => formatValue(v, fmt).text
eq(fv(1234.567, '#,##0.00'), '1,234.57', '千分位'); eq(fv(-1234.5, '"¥"#,##0.00'), '-¥1,234.50', '货币')
eq(fv(0.1234, '0.00%'), '12.34%', '百分比'); eq(fv(12345, '0.00E+00'), '1.23E+04', '科学计数')
eq(fv(45292, 'yyyy-mm-dd'), '2024-01-01', '日期'); eq(fv(45292.5, 'yyyy/m/d hh:mm'), '2024/1/1 12:00', '日期时间')
eq(fv(0.75, 'h:mm:ss'), '18:00:00', '时间'); eq(fv(-5, '0;[Red](0)'), '(5)', '负数分段'); eq(formatValue(-5, '0;[Red](0)').color, '#e11d48', '红色')
eq(fv(0, '0.0;-0.0;"-"'), '-', '零分段'); eq(fv('abc', '@'), 'abc', '文本'); eq(fv(1 / 3, 'General'), '0.3333333333', '常规')
eq(fv(0.5, '0'), '1', '取整'); eq(fv(1234.5, '#,##0'), '1,235', '千分位取整'); eq(fv(45292, 'yyyy"年"m"月"d"日"'), '2024年1月1日', '中文日期')

console.log(`\n公式测试：${pass} 通过，${fail} 失败`)
process.exit(fail ? 1 : 0)
