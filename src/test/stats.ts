import {table} from 'table';
import {Stats} from 'trakr';

// Separate outliers from clean samples using MAD outlier detection with what is
// approximately a three-sigma cutoff (corresponding to roughly ~99.7% of values
// assuming the data is normally distributed), as out forth in "Detecting
// outliers: Do not use standard deviation around the mean, use absolute
// deviation around the median" - C. Leys et al
const clean = (samples: number[], n = 3) => {
  const stats = Stats.compute(samples);
  const deviations = samples.map(s => Math.abs(s - stats.p50));
  const mad = Stats.median(deviations);
  const b = n * 1.4826;
  const cleaned: number[] = [];
  const outliers: number[] = [];
  for (let i = 0; i < samples.length; i++) {
    (deviations[i] / mad > b ? outliers : cleaned).push(samples[i]);
  }
  return [cleaned, outliers];
};

export const summarize = (name: string, samples: number[], summary: 'text' | 'json') => {
  const [cleaned, outliers] = clean(samples);
  const stats = Stats.compute(cleaned);
  let extra = `[${stats.min} .. ${stats.max}]`;
  if (outliers.length) {
    extra += summary === 'text'
      ? ` (${outliers.length})`
      : ` (dropped: ${outliers.sort().join(', ')})`;
  }

  return {
    name,
    unit: 'battles/sec',
    value: Math.round(stats.avg),
    range: isNaN(stats.rme) ? 'N/A' : `±${stats.rme.toFixed(2)}%`,
    extra,
  };
};

// Critical Mann-Whitney U-values for 95% confidence.
// For more info see http://www.saburchill.com/IBbiology/stats/003.html.
/* eslint-disable */
const TABLE = [
  [0, 1, 2],
  [1, 2, 3, 5],
  [1, 3, 5, 6, 8],
  [2, 4, 6, 8, 10, 13],
  [2, 4, 7, 10, 12, 15, 17],
  [3, 5, 8, 11, 14, 17, 20, 23],
  [3, 6, 9, 13, 16, 19, 23, 26, 30],
  [4, 7, 11, 14, 18, 22, 26, 29, 33, 37],
  [4, 8, 12, 16, 20, 24, 28, 33, 37, 41, 45],
  [5, 9, 13, 17, 22, 26, 31, 36, 40, 45, 50, 55],
  [5, 10, 14, 19, 24, 29, 34, 39, 44, 49, 54, 59, 64],
  [6, 11, 15, 21, 26, 31, 37, 42, 47, 53, 59, 64, 70, 75],
  [6, 11, 17, 22, 28, 34, 39, 45, 51, 57, 63, 67, 75, 81, 87],
  [7, 12, 18, 24, 30, 36, 42, 48, 55, 61, 67, 74, 80, 86, 93, 99],
  [7, 13, 19, 25, 32, 38, 45, 52, 58, 65, 72, 78, 85, 92, 99, 106, 113],
  [8, 14, 20, 27, 34, 41, 48, 55, 62, 69, 76, 83, 90, 98, 105, 112, 119, 127],
  [8, 15, 22, 29, 36, 43, 50, 58, 65, 73, 80, 88, 96, 103, 111, 119, 126, 134, 142],
  [9, 16, 23, 30, 38, 45, 53, 61, 69, 77, 85, 93, 101, 109, 117, 125, 133, 141, 150, 158],
  [9, 17, 24, 32, 40, 48, 56, 64, 73, 81, 89, 98, 106, 115, 123, 132, 140, 149, 157, 166, 175],
  [10, 17, 25, 33, 42, 50, 59, 67, 76, 85, 94, 102, 111, 120, 129, 138, 147, 156, 165, 174, 183, 192],
  [10, 18, 27, 35, 44, 53, 62, 71, 80, 89, 98, 107, 117, 126, 135, 145, 154, 163, 173, 182, 192, 201, 211],
  [11, 19, 28, 37, 46, 55, 64, 74, 83, 93, 102, 112, 122, 132, 141, 151, 161, 171, 181, 191, 200, 210, 220, 230],
  [11, 20, 29, 38, 48, 57, 67, 77, 87, 97, 107, 118, 125, 138, 147, 158, 168, 178, 188, 199, 209, 219, 230, 240, 250],
  [12, 21, 30, 40, 50, 60, 70, 80, 90, 101, 111, 122, 132, 143, 154, 164, 175, 186, 196, 207, 218, 228, 239, 250, 261, 272],
  [13, 22, 32, 42, 52, 62, 73, 83, 94, 105, 116, 127, 138, 149, 160, 171, 182, 193, 204, 215, 226, 238, 249, 260, 271, 282, 294],
  [13, 23, 33, 43, 54, 65, 76, 87, 98, 109, 120, 131, 143, 154, 166, 177, 189, 200, 212, 223, 235, 247, 258, 270, 282, 293, 305, 317],
];
/* eslint-enable */

const utest = (control: number[], test: number[]) => {
  if (control === test) return 0;

  const cc = control.length;
  const ct = test.length;
  const max = Math.max(cc, ct);
  const min = Math.min(cc, ct);

  const score = (x: number, ys: number[]) =>
    ys.reduce((sum, y) => sum + (y > x ? 0 : y < x ? 1 : 0.5), 0);
  const U = (xs: number[], ys: number[]) =>
    xs.reduce((sum, x) => sum + score(x, ys), 0);
  const uc = U(control, test);
  const ut = U(test, control);
  const u = Math.min(uc, ut);

  // Reject the null hypothesis the two samples come from the
  // same population (i.e. have the same median) if...
  if (cc + ct > 30) {
    // ...the z-stat is greater than 1.96 or less than -1.96
    // http://www.statisticslectures.com/topics/mannwhitneyu/
    const Z = (v: number) =>
      (v - ((cc * ct) / 2)) / Math.sqrt((cc * ct * (cc + ct + 1)) / 12);
    return Math.abs(Z(u)) > 1.96 ? (u === uc ? 1 : -1) : 0;
  }
  // ...the U value is less than or equal the critical U value.
  const critical = max < 5 || min < 3 ? 0 : TABLE[max - 5][min - 3];
  return u <= critical ? (u === uc ? 1 : -1) : 0;
};

// Percentile bootstrap confidence interval
const bootstrap = (
  control: number[], test: number[],
  random?: (min: number, max: number) => number
) => {
  const N = 1000;
  const d50 = new Array(N);
  const d90 = new Array(N);
  const d95 = new Array(N);
  const d99 = new Array(N);

  if (!random) {
    random = (min: number, max: number) => {
      min = Math.ceil(min);
      max = Math.floor(max);
      return Math.floor(Math.random() * (max - min)) + min;
    };
  }

  const sample = (arr: number[], n: number) => {
    const sampled = [];
    const length = arr.length;
    for (let i = 0; i < n; i++) {
      sampled.push(arr[random!(0, length)]);
    }
    return sampled;
  };

  const percentiles = (arr: number[]) => {
    arr.sort((a, b) => a - b);
    return {
      p50: Stats.ptile(arr, 0.50),
      p90: Stats.ptile(arr, 0.90),
      p95: Stats.ptile(arr, 0.95),
      p99: Stats.ptile(arr, 0.99),
    };
  };

  const cc = Math.floor(control.length / 3);
  const ct = Math.floor(test.length / 3);
  for (let i = 0; i < N; i++) {
    const qc = percentiles(sample(control, cc));
    const qt = percentiles(sample(test, ct));

    d50[i] = qc.p50 - qt.p50;
    d90[i] = qc.p90 - qt.p90;
    d95[i] = qc.p95 - qt.p95;
    d99[i] = qc.p99 - qt.p99;
  }

  const md50 = Stats.mean(d50);
  const md90 = Stats.mean(d90);
  const md95 = Stats.mean(d95);
  const md99 = Stats.mean(d99);

  const ci = (d: number[], m: number) =>
    1.96 * Stats.standardDeviation(d, false, m);

  return {
    d50: md50,
    d90: md90,
    d95: md95,
    d99: md99,
    ci50: ci(d50, md50),
    ci90: ci(d90, md90),
    ci95: ci(d95, md95),
    ci99: ci(d99, md99),
  };
};

const GFM = {
  border: {
    bodyLeft: '|', bodyRight: '|', bodyJoin: '|',
    joinBody: '-', joinLeft: '|', joinRight: '|', joinJoin: '|',
  },
  drawHorizontalLine: (index: number) => index === 1,
};

const toTable = (header: string[], data: string[][], md?: boolean, maxWidth = 20) => {
  if (md) return table([header.map(s => `${BOLD}${s}${RESET}`), ...data], GFM);

  const maxes = (new Array(header.length)).fill(-Infinity);
  const combined: string[][] = [header, ...data];
  for (const row of combined) {
    for (let i = 0; i < row.length; i++) {
      const s = unescape(row[i]);
      const len = s.length > maxWidth ? Stats.max(s.split(' ').map(c => c.length)) : s.length;
      if (len > maxes[i]) maxes[i] = len;
    }
  }

  return table([header.map(s => `${BOLD}${s}${RESET}`), ...data], {
    columns: maxes.map(max => ({
      wrapWord: true,
      width: Math.min(max, maxWidth),
    })),
  });
};

export const decimal = (n: number, c = 100) => {
  if (n < 1) return n.toFixed(3);
  if (n < 10) return n.toFixed(2);
  if (n < c) return n.toFixed(1);
  return n.toFixed();
};

const percent = (n: number, d: number) => `${(n * 100 / d).toFixed(2)}%`;

const diff = (num: number, ci: number, percentile: number, md?: boolean) => {
  const diffp = percent(num, percentile);
  const cip = percent(ci, percentile);
  return color(num, ci, md)(`${diffp} ± ${cip}`);
};

// eslint-disable-next-line
const ESCAPE = /[\u001b\u009b][[()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]/g;
const unescape = (s: string) => s.replaceAll(ESCAPE, '');

const RED = '\x1b[31m';
const GREEN = '\x1b[32m';
const BOLD = '\x1b[1m';
const RESET = '\x1b[0m';

const color = (num: number, ci: number, md?: boolean) => {
  const red = (s: string) => md ? s : `${RED}${s}${RESET}`;
  const green = (s: string) => md ? s : `${GREEN}${s}${RESET}`;
  const none = (s: string) => s;
  return ((num - ci < 0 && num + ci < 0)
    ? green
    : (num - ci > 0 && num + ci > 0) ? red : none);
};

export const regression = (
  before: {[name: string]: number[]},
  after: {[name: string]: number[]},
  random: (min: number, max: number) => number
) => {
  if (Object.keys(before).length !== Object.keys(after).length) {
    throw new Error('Can\'t compare two incompatible samples');
  }

  const print = (when: string, result: -1 | 0 | 1, summary: ReturnType<typeof summarize>) => {
    const {range, value, unit, extra} = summary;
    const r = range.startsWith('±') ? ` ± ${range.slice(1)}` : '';
    const w = when === 'After';
    const [b, e] =
      result === 0 ? ['', ''] : [result < 0 ? (w ? RED : GREEN) : (w ? GREEN : RED), RESET];
    console.log(`${BOLD}${when}${RESET}: ${b}${value}${r} ${unit}${e} ${extra}`);
  };

  const display = (control: number[], test: number[]) => {
    const stats = Stats.compute(control);
    const result = bootstrap(control, test, random);

    console.log(toTable(
      ['d50', 'd90', 'd95', 'd99'], [[
        diff(result.d50, result.ci50, stats.p50, false),
        diff(result.d90, result.ci90, stats.p90, false),
        diff(result.d95, result.ci95, stats.p95, false),
        diff(result.d99, result.ci99, stats.p99, false),
      ]],
      false
    ));
  };

  console.log();
  for (const name in before) {
    if (!after[name] || before[name].length !== after[name].length) {
      throw new Error(`Can't compare two incompatible samples for '${name}'`);
    }

    // // TODO: consider outlier removal before testing for signficance?
    // const cleaned = {before: clean(before[name])[0], after: clean(after[name])[0]};

    console.log(`${BOLD}${name}\n${'-'.repeat(name.length)}${RESET}\n`);
    const result = utest(before[name], after[name]);
    print('Before', result, summarize(name, before[name], 'text'));
    print('After', result, summarize(name, after[name], 'text'));

    console.log();
    display(before[name], after[name]);
  }
};
