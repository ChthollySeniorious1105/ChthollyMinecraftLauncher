// 最小 7z 写出器：LZMA 以外的 Copy（不压缩）编码，单一 folder、每个文件一个 packed stream
// 7z 格式参考：7zFormat.txt（Igor Pavlov）
import { crc32 } from './crc32.js'

const writeNumber = (out, v) => {
    // 7z UINT64 可变长编码
    v = BigInt(v)
    if (v < 0x80n) { out.push(Number(v)); return }
    let n = 1
    while (n < 8 && v >= (1n << BigInt(7 * (n + 1)))) n++
    if (n >= 8) {
        out.push(0xff)
        for (let i = 0; i < 8; i++) out.push(Number((v >> BigInt(8 * i)) & 0xffn))
        return
    }
    const high = Number(v >> BigInt(8 * n))
    out.push((0xff << (8 - n)) & 0xff | high)
    for (let i = 0; i < n; i++) out.push(Number((v >> BigInt(8 * i)) & 0xffn))
}
const u32 = (out, v) => { for (let i = 0; i < 4; i++) out.push((v >>> (8 * i)) & 0xff) }
const u64 = (out, v) => { v = BigInt(v); for (let i = 0; i < 8; i++) out.push(Number((v >> BigInt(8 * i)) & 0xffn)) }

// files: [{ pathname, data: Uint8Array }]
export function write7z(files) {
    files = files.filter(f => f.data.length > 0 || true)
    const nonEmpty = files.filter(f => f.data.length > 0)
    const packed = nonEmpty.reduce((s, f) => s + f.data.length, 0)
    const h = []
    h.push(0x01) // Header
    if (nonEmpty.length) {
        h.push(0x04) // MainStreamsInfo
        // PackInfo
        h.push(0x06); writeNumber(h, 0); writeNumber(h, nonEmpty.length)
        h.push(0x09); for (const f of nonEmpty) writeNumber(h, f.data.length)
        h.push(0x00)
        // UnPackInfo：每个文件一个 folder，coder = Copy (0x00)
        h.push(0x07); h.push(0x0b); writeNumber(h, nonEmpty.length); h.push(0x00)
        for (let i = 0; i < nonEmpty.length; i++) { writeNumber(h, 1); h.push(0x01, 0x00) }
        h.push(0x0c); for (const f of nonEmpty) writeNumber(h, f.data.length)
        h.push(0x00)
        // SubStreamsInfo：每个 folder 一个流（部分解压器要求此块存在），CRC 写在这里
        h.push(0x08)
        h.push(0x0d); for (let i = 0; i < nonEmpty.length; i++) writeNumber(h, 1)
        h.push(0x0a, 0x01); for (const f of nonEmpty) u32(h, crc32(f.data))
        h.push(0x00)
        h.push(0x00) // end StreamsInfo
    }
    // FilesInfo
    h.push(0x05); writeNumber(h, files.length)
    const empty = files.map(f => f.data.length === 0)
    if (empty.some(Boolean)) {
        const bits = bitVector(empty)
        h.push(0x0e); writeNumber(h, bits.length); h.push(...bits)
        // 空文件（而不是目录）
        const emptyFiles = bitVector(files.filter((_, i) => empty[i]).map(() => true))
        h.push(0x0f); writeNumber(h, emptyFiles.length); h.push(...emptyFiles)
    }
    // 文件名（UTF-16LE，以 0 结尾）
    const names = []
    names.push(0x00) // external = 0
    for (const f of files) {
        const n = f.pathname.replace(/\\/g, '/')
        for (let i = 0; i < n.length; i++) { const c = n.charCodeAt(i); names.push(c & 0xff, c >> 8) }
        names.push(0, 0)
    }
    h.push(0x11); writeNumber(h, names.length); h.push(...names)
    // 修改时间（当前时间，Windows FILETIME）
    const ft = BigInt(Date.now()) * 10000n + 116444736000000000n
    const times = [0x01, 0x00] // allDefined, external = 0
    for (let i = 0; i < files.length; i++) u64(times, ft)
    h.push(0x14); writeNumber(h, times.length); h.push(...times)
    h.push(0x00) // end FilesInfo
    h.push(0x00) // end Header
    const header = new Uint8Array(h)

    const total = 32 + packed + header.length
    const out = new Uint8Array(total)
    let o = 32
    for (const f of nonEmpty) { out.set(f.data, o); o += f.data.length }
    out.set(header, o)
    // Signature header
    const sig = [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 0x00, 0x04]
    out.set(sig, 0)
    const next = []
    u64(next, packed); u64(next, header.length); u32(next, crc32(header))
    const nextArr = new Uint8Array(next)
    const sc = []
    u32(sc, crc32(nextArr))
    out.set(sc, 8)
    out.set(nextArr, 12)
    return out
}

function bitVector(bools) {
    const out = []
    for (let i = 0; i < bools.length; i += 8) {
        let b = 0
        for (let j = 0; j < 8 && i + j < bools.length; j++) if (bools[i + j]) b |= 0x80 >> j
        out.push(b)
    }
    return out
}
