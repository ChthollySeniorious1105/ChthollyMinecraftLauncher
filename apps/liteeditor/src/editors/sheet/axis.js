// 行 / 列轴几何：默认尺寸 + 稀疏的自定义尺寸与隐藏，支持百万级行列的 O(log n) 定位
export class Axis {
    constructor() { this.def = 24; this.sizes = new Map(); this.hidden = new Set(); this.hidden2 = null; this.idx = []; this.cum = []; this.sz = []; this.total = 0 }

    // 仅当输入对象发生变化时重建索引
    sync(def, sizes, hidden, hidden2) {
        if (def === this.def && sizes === this.sizes && hidden === this.hidden && hidden2 === this.hidden2) return
        this.def = def; this.sizes = sizes; this.hidden = hidden; this.hidden2 = hidden2
        const keys = new Set(sizes.keys())
        for (const k of hidden) keys.add(k)
        if (hidden2) for (const k of hidden2) keys.add(k)
        const idx = [...keys].sort((a, b) => a - b)
        this.idx = idx
        this.sz = idx.map(i => this.isHidden(i) ? 0 : sizes.get(i) ?? def)
        this.cum = new Array(idx.length)
        let acc = 0
        for (let k = 0; k < idx.length; k++) { this.cum[k] = acc; acc += this.sz[k] - def }
        this.total = acc
    }

    isHidden(i) { return this.hidden.has(i) || !!this.hidden2?.has(i) }
    size(i) {
        if (this.isHidden(i)) return 0
        return this.sizes.get(i) ?? this.def
    }
    // 第一个 >= i 的覆盖项下标
    #lower(i) {
        let lo = 0, hi = this.idx.length
        while (lo < hi) { const m = (lo + hi) >> 1; if (this.idx[m] < i) lo = m + 1; else hi = m }
        return lo
    }
    // 第 i 项的起始位置
    pos(i) {
        const k = this.#lower(i)
        const delta = k < this.idx.length ? this.cum[k] : this.total ?? 0
        return i * this.def + delta
    }
    // 位置 y 所在的项
    at(y) {
        if (y <= 0) return 0
        const idx = this.idx
        // 找到最后一个起始位置 <= y 的覆盖项
        let lo = 0, hi = idx.length - 1, k = -1
        while (lo <= hi) {
            const m = (lo + hi) >> 1
            if (idx[m] * this.def + this.cum[m] <= y) { k = m; lo = m + 1 } else hi = m - 1
        }
        if (k < 0) return Math.floor(y / this.def)
        const p = idx[k] * this.def + this.cum[k]
        if (y < p + this.sz[k]) return idx[k]
        const rest = y - p - this.sz[k]
        let i = idx[k] + 1 + Math.floor(rest / this.def)
        // 跳过紧随其后的隐藏项
        while (k + 1 < idx.length && idx[k + 1] <= i && this.sz[k + 1] === 0 && idx[k + 1] === i) { i++; k++ }
        return i
    }
    // 从 i 起向 dir 方向找第一个可见项
    visible(i, dir = 1, max = 1048575) {
        while (i >= 0 && i <= max && this.isHidden(i)) i += dir
        return i < 0 ? this.visible(0, 1, max) : Math.min(i, max)
    }
}
