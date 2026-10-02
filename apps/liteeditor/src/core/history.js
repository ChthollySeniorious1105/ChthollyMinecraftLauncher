// 快照式撤销栈：每次修改后 push 修改后的状态快照；撤销即恢复上一个快照
// 快照的具体内容由各编辑器决定（可以共享未修改部分以节省内存）
export class History {
    constructor({ limit = 80, onChange } = {}) {
        this.limit = limit
        this.onChange = onChange
        this.stack = []
        this.index = -1
    }

    reset(snap, label = '打开') {
        this.stack = [{ label, snap, time: Date.now() }]
        this.index = 0
        this.onChange?.()
    }

    push(label, snap) {
        this.stack.splice(this.index + 1)
        this.stack.push({ label, snap, time: Date.now() })
        while (this.stack.length > Math.max(2, this.limit)) this.stack.shift()
        this.index = this.stack.length - 1
        this.onChange?.()
    }

    // 用新快照替换当前记录（连续的同类操作合并为一步，例如拖动滑块）
    replace(snap, label) {
        const cur = this.stack[this.index]
        if (!cur) return this.push(label, snap)
        cur.snap = snap
        if (label) cur.label = label
        cur.time = Date.now()
        this.onChange?.()
    }

    get current() { return this.stack[this.index] ?? null }
    get canUndo() { return this.index > 0 }
    get canRedo() { return this.index < this.stack.length - 1 }

    undo() {
        if (!this.canUndo) return null
        this.index--
        this.onChange?.()
        return this.stack[this.index].snap
    }

    redo() {
        if (!this.canRedo) return null
        this.index++
        this.onChange?.()
        return this.stack[this.index].snap
    }

    goto(i) {
        if (i < 0 || i >= this.stack.length || i === this.index) return null
        this.index = i
        this.onChange?.()
        return this.stack[i].snap
    }
}
