// 文本解码：自动识别 UTF-8 / UTF-16 / GBK / Big5 / Shift_JIS 等编码
import jschardet from 'jschardet'

const MAP = {
    'utf-8': 'utf-8', ascii: 'utf-8', 'utf-16le': 'utf-16le', 'utf-16be': 'utf-16be',
    gb2312: 'gb18030', gbk: 'gb18030', gb18030: 'gb18030', big5: 'big5',
    shift_jis: 'shift_jis', 'euc-jp': 'euc-jp', 'euc-kr': 'euc-kr', 'iso-2022-jp': 'iso-2022-jp',
    'windows-1252': 'windows-1252', 'iso-8859-1': 'windows-1252', 'windows-1251': 'windows-1251',
    'koi8-r': 'koi8-r', 'iso-8859-2': 'iso-8859-2', 'windows-1250': 'windows-1250',
}

export function detectEncoding(bytes) {
    if (bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) return 'utf-8'
    if (bytes[0] === 0xff && bytes[1] === 0xfe) return 'utf-16le'
    if (bytes[0] === 0xfe && bytes[1] === 0xff) return 'utf-16be'
    // 先严格按 UTF-8 解码尝试
    try {
        new TextDecoder('utf-8', { fatal: true }).decode(bytes.subarray(0, Math.min(bytes.length, 256 * 1024)))
        return 'utf-8'
    } catch (e) {
        // 截断在多字节字符中间也会失败，下面再判断
        if (bytes.length > 256 * 1024) {
            try {
                new TextDecoder('utf-8', { fatal: true }).decode(bytes.subarray(0, 256 * 1024 - 4))
                return 'utf-8'
            } catch { /* 非 UTF-8 */ }
        }
    }
    const sample = bytes.subarray(0, Math.min(bytes.length, 64 * 1024))
    let bin = ''
    for (let i = 0; i < sample.length; i += 8192)
        bin += String.fromCharCode.apply(null, sample.subarray(i, i + 8192))
    const r = jschardet.detect(bin)
    const enc = MAP[(r?.encoding ?? '').toLowerCase()]
    return enc ?? 'gb18030'
}

export function decodeText(buffer, encoding) {
    const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer)
    const enc = encoding ?? detectEncoding(bytes)
    try {
        return { text: new TextDecoder(enc).decode(bytes), encoding: enc }
    } catch {
        return { text: new TextDecoder('utf-8').decode(bytes), encoding: 'utf-8' }
    }
}

export const ENCODINGS = [
    ['utf-8', 'UTF-8'], ['gb18030', 'GBK / GB18030'], ['big5', 'Big5 繁体'],
    ['utf-16le', 'UTF-16 LE'], ['utf-16be', 'UTF-16 BE'], ['shift_jis', 'Shift_JIS 日文'],
    ['euc-kr', 'EUC-KR 韩文'], ['windows-1252', 'Western (1252)'], ['windows-1251', 'Cyrillic (1251)'],
]
