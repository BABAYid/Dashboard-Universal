// ============================================================================
//  Генерация SDF-глифов для MapLibre (формат maptiler: {fontstack}/{range}.pbf).
//
//  Нужна для подписей улиц: MapLibre не умеет рисовать текст без глифов.
//  Глифы генерируются один раз и коммитятся в Dashboard/map/fonts/<stack>/.
//  Сервер тайлов отдаёт их по /fonts/{fontstack}/{range}.pbf.
//
//  Запуск (fontnik ставится в build/, т.к. он в .gitignore):
//      cd build && npm install fontnik --cache npm-cache
//      cd .. && node tools/nav-glyphs.js \
//          /usr/share/fonts/truetype/lato/Lato-Regular.ttf \
//          Dashboard/map/fonts/Lato
//
//  В наборе — латиница, пунктуация и кириллица (U+0400…U+04FF).
// ============================================================================
// Генерация SDF-глифов для MapLibre (формат maptiler: {fontstack}/{range}.pbf).
// Запуск: node tools/nav-glyphs.js <font.ttf> <outdir>
const fontnik = require('fontnik');
const fs = require('fs');
const path = require('path');

const [, , fontPath, outDir] = process.argv;
if (!fontPath || !outDir) {
  console.error('usage: node glyphs.js <font.ttf> <outdir>');
  process.exit(1);
}
const font = fs.readFileSync(fontPath);
fs.mkdirSync(outDir, { recursive: true });

// Диапазоны кратны 256; MapLibre так и запрашивает. Кириллица U+0400…U+04FF
// попадает в 1024-1279, пунктуация и № — в 8192-8703.
const ranges = [
  [0, 255], [256, 511], [512, 767], [768, 1023],
  [1024, 1279], [1280, 1535],
  [8192, 8447], [8448, 8703],
];

let pending = ranges.length;
let failed = 0;
for (const [s, e] of ranges) {
  fontnik.range({ font, start: s, end: e }, (err, buf) => {
    if (err) {
      console.error('range', s, e, err);
      failed = 1;
    } else {
      fs.writeFileSync(path.join(outDir, `${s}-${e}.pbf`), buf);
      console.log(`${s}-${e}.pbf`, buf.length, 'байт');
    }
    if (--pending === 0) {
      process.exitCode = failed;
      console.log(failed ? 'ОШИБКА' : 'готово');
    }
  });
}
