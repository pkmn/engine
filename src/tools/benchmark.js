/* eslint-disable max-len */
const DATA = {
  'RBY': [0.21, 32.10],
  'GSC': [0.32, 33.23],
  'ADV': [0.29, 35.46],
  'DPP': [0.40, 40.32],
  'B/W': [0.35, 38.89],
  'X/Y': [0.35, 37.96],
  'S/M': [0.43, 40.12],
  'S/S': [0.40, 41.53],
};

let max = 0;
for (const gen in DATA) {
  const [pkmn, ps] = DATA[gen];
  max = Math.max(max, pkmn, ps);
}
max = Math.floor(max / 10) * 10;

const WIDTH = 800;
const PADDING = {w: 120, h: 25, text: 8};
const DIVIDERS = max / 10 + 1;
const STRIDE = (WIDTH - (2 * PADDING.w) - ((DIVIDERS - 1) / 2)) / (DIVIDERS - 1);
const BAR = {h: 14, pad: 6};
const ROW = (BAR.h + BAR.pad) * 2 + 1;
const SCALE = (STRIDE * (DIVIDERS - 1)) / max;
const UNPADDED = ROW * Object.keys(DATA).length;
const height = UNPADDED + PADDING.h * 2 - (BAR.h + BAR.pad);

console.error(height, UNPADDED, ROW);

const HEADER =
`<svg xmlns="http://www.w3.org/2000/svg"
  font-family="Roboto, Helvetica, Arial, sans-serif"
  font-size="13px"
  fill="#000000"
  width="${WIDTH}"
  height="${height}"
>
  <style>
    @media (prefers-color-scheme: dark) {
      #bg { fill: #0D1116; }
      text { fill: #C9D1D9; }
    }
  </style>
  <rect id="bg" width="${WIDTH}" height="${height}" fill="#FFFFFF" />`;

const out = [HEADER];
for (let i = 0; i < DIVIDERS; i++) {
  out.push(`  <rect x="${PADDING.w + STRIDE * i}" y="${BAR.h + BAR.pad}" width="1" height="${UNPADDED - (BAR.h + BAR.pad)}" fill="#7F7F7F" fill-opacity="0.25" />`);
  out.push(`  <text x="${PADDING.w + STRIDE * i}" y="${UNPADDED + 4}" text-anchor="middle" dominant-baseline="hanging">${i * 10}s</text>`);
}

let y = (BAR.h + BAR.pad) - (BAR.pad / 2);
for (const gen in DATA) {
  const [pkmn, ps] = DATA[gen];

  let width = pkmn * SCALE;

  y += BAR.pad;
  out.push(` <rect x="${PADDING.w}" y="${y}" width="${width}" height="${BAR.h}" fill="#1976D2"/>`);
  out.push(` <text x="${width + PADDING.w + PADDING.text}" y="${y + (BAR.h / 2)}" dominant-baseline="middle">${pkmn}s</text>`);
  y += BAR.h;

  out.push(` <text x="${PADDING.w - PADDING.text}" y="${y + 1}" text-anchor="end" dominant-baseline="middle">${gen}</text>`);

  width = ps * SCALE;

  y += 2;
  out.push(` <rect x="${PADDING.w}" y="${y}" width="${width}" height="${BAR.h}" fill="#D32F2F"/>`);
  out.push(` <text x="${width + PADDING.w + PADDING.text}" y="${y + (BAR.h / 2)}" dominant-baseline="middle">${ps}s</text>`);
  y += BAR.h;
}

out.push('</svg>');

console.log(out.join('\n'));
