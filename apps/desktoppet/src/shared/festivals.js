// Festival calendar shared by the pet window and the hub (window.PetFestivals).
// Gregorian festivals + lunar festivals via Intl's Chinese calendar (no data tables needed).
(function () {
  const SOLAR = [
    [1, 1, '元旦'], [2, 14, '情人节'], [3, 8, '妇女节'], [3, 12, '植树节'], [4, 1, '愚人节'], [5, 1, '劳动节'], [5, 4, '青年节'],
    [6, 1, '儿童节'], [7, 1, '建党节'], [8, 1, '建军节'], [9, 10, '教师节'], [10, 1, '国庆节'], [10, 31, '万圣夜'], [12, 24, '平安夜'], [12, 25, '圣诞节']
  ];
  const LUNAR = [[1, 1, '春节'], [1, 15, '元宵节'], [2, 2, '龙抬头'], [5, 5, '端午节'], [7, 7, '七夕'], [7, 15, '中元节'], [8, 15, '中秋节'], [9, 9, '重阳节'], [12, 8, '腊八节'], [12, 23, '小年']];
  const LUNAR_MONTH = ['正', '二', '三', '四', '五', '六', '七', '八', '九', '十', '冬', '腊'];
  const LUNAR_DAY = ['初一', '初二', '初三', '初四', '初五', '初六', '初七', '初八', '初九', '初十', '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十', '廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九', '三十'];
  let lunarFmt = null;
  try { lunarFmt = new Intl.DateTimeFormat('zh-CN-u-ca-chinese', { month: 'numeric', day: 'numeric' }); } catch { lunarFmt = null; }
  function lunarOf(d) {
    if (!lunarFmt) return null;
    const parts = lunarFmt.formatToParts(d);
    const m = parts.find(p => p.type === 'month'), dd = parts.find(p => p.type === 'day');
    if (!m || !dd) return null;
    const leap = /闰|bis/i.test(m.value);
    return { month: parseInt(m.value.replace(/\D/g, ''), 10), day: parseInt(dd.value, 10), leap };
  }
  // 清明: approx 4/4-4/6 using the standard formula
  function qingming(y) { const c = y % 100; return Math.floor(c * 0.2422 + 4.81) - Math.floor((c - 1) / 4); }
  function festivalsOn(d) {
    const out = [];
    const m = d.getMonth() + 1, day = d.getDate();
    for (const [fm, fd, n] of SOLAR) if (fm === m && fd === day) out.push(n);
    if (m === 4 && day === qingming(d.getFullYear())) out.push('清明节');
    // 母亲节: 2nd Sunday of May; 父亲节: 3rd Sunday of June
    if (d.getDay() === 0 && m === 5 && day > 7 && day <= 14) out.push('母亲节');
    if (d.getDay() === 0 && m === 6 && day > 14 && day <= 21) out.push('父亲节');
    const l = lunarOf(d);
    if (l && !l.leap) {
      for (const [lm, ld, n] of LUNAR) if (lm === l.month && ld === l.day) out.push(n);
      // 除夕: the day before 春节
      const next = lunarOf(new Date(d.getTime() + 864e5));
      if (next && next.month === 1 && next.day === 1 && !next.leap) out.push('除夕');
    }
    return out;
  }
  window.PetFestivals = { festivalsOn, lunarOf, LUNAR_MONTH, LUNAR_DAY };
})();
