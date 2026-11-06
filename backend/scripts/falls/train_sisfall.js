/**
 * Train the deployed fall model from SisFall feature rows.
 * Raw SisFall files are intentionally not bundled with the source delivery;
 * put them under data/falls/raw/SisFall or provide a grouped feature CSV.
 */
import fs from 'node:fs';
import os from 'node:os';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { convertIfPresent } from './convert_sisfall.js';
import { parseCsv, trainFromRows } from './train.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const RAW = path.join(ROOT, 'data/falls/raw/SisFall');
const PREPARED_CSV = Boolean(process.env.SISFALL_FEATURE_CSV);
const DATA_CSV = path.resolve(process.env.SISFALL_FEATURE_CSV || path.join(ROOT, 'data/falls/dataset.csv'));
const MODEL_PATH = path.join(ROOT, 'src/services/fallDetection/model.json');
const REPORT_PATH = path.resolve(ROOT, '../docs/phase3/04-sisfall-training-report.md');
const SWEEP_PATH = path.resolve(ROOT, '../docs/evaluation/fall-rule-threshold-sweep.csv');
const OOF_PATH = path.resolve(ROOT, '../docs/evaluation/fall-out-of-fold-scores.csv');
const SOURCE_REVISION = 'f8a95e5c953169985dc9641e1a5772e6b7b47a83';
const SOURCE_ARCHIVE_URL = `https://huggingface.co/datasets/Trupal7/Sisfall_Dataset/resolve/${SOURCE_REVISION}/SisFall_dataset.zip`;
const SOURCE_ARCHIVE_SHA256 = '7f0dd1583e39fee0f402a6855976eb12517f7eaecdacce871d5b3421793ad665';

function pct(value) {
  return `${(value * 100).toFixed(2)}%`;
}

export function outOfFoldCsv(rows) {
  const csvCell = (value) => {
    let text = String(value ?? '');
    if (typeof value === 'string' && /^[=+@\-\t\r]/.test(text)) text = "'" + text;
    return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
  };
  return ['fold,subject_id,label,margin,agree_ratio', ...rows.map((row) =>
    [row.fold, row.subjectId, row.label, row.margin, row.agreeRatio].map(csvCell).join(','),
  )].join('\n') + '\n';
}

export function thresholdSweepCsv(rows) {
  const header = [
    'margin_threshold', 'agree_ratio_threshold', 'sensitivity', 'false_positive_rate',
    'precision', 'accuracy', 'f1', 'tp', 'fp', 'fn', 'tn', 'source',
  ];
  return [
    header.join(','),
    ...rows.map((row) => [
      row.marginThreshold,
      row.agreeThreshold,
      row.recall.toFixed(4),
      row.falsePositiveRate.toFixed(4),
      row.precision.toFixed(4),
      row.accuracy.toFixed(4),
      row.f1.toFixed(4),
      row.tp, row.fp, row.fn, row.tn, row.source,
    ].join(',')),
  ].join('\n') + '\n';
}

function writeReport(model, rowCount) {
  const knn = model.cv.knn;
  const svm = model.cv.svm;
  const ensemble = model.cv.ensemble;
  const inputProvenance = PREPARED_CSV
    ? 'ورودی از مسیر `SISFALL_FEATURE_CSV` داده شده است. این اسکریپت وجود `subject_id` و `recording_id` را بررسی می‌کند، اما منشأ یا hash فایل CSV آماده را تأیید نمی‌کند؛ منشأ آن باید جداگانه ثبت شود.'
    : 'مسیر پیش‌فرض، ضبط‌های خام را از آرشیو mirror زیر دریافت می‌کند. نسخهٔ mirror ثابت است و hash آرشیو ZIP برابر ' + SOURCE_ARCHIVE_SHA256 + ' است. خود اسکریپت hash آرشیو را کنترل نمی‌کند؛ این hash برای کنترل دانلود در راهنمای `backend/data/falls/README.md` آمده است.';
  const report = `# گزارش بازتولید آموزش مدل سقوط SisFall

این گزارش با اجرای \`npm run train:fall:sisfall\` تولید شده است.

## منشأ داده و بازتولید

دادهٔ خام در مخزن نگهداری نمی‌شود. منبع قابل‌بازتولید، mirror مجموعه در [Hugging Face](https://huggingface.co/datasets/Trupal7/Sisfall_Dataset/tree/${SOURCE_REVISION}) و آرشیو [SisFall_dataset.zip](${SOURCE_ARCHIVE_URL}) در commit ثابت \`${SOURCE_REVISION}\` است. کارت این mirror مجوز CC BY 4.0 را اعلام می‌کند؛ مقالهٔ اصلی SisFall را [Sucerquia و همکاران، ۲۰۱۷](https://doi.org/10.3390/s17010198) ارجاع دهید. ${inputProvenance}

README داخل آرشیو ۴٬۵۱۰ فایل را اعلام می‌کند، اما در همین revision تعداد فایل‌های ضبط با نام‌گذاری داده ۴٬۵۰۵ است: ۱٬۷۹۸ سقوط شبیه‌سازی‌شده و ۲٬۷۰۷ فعالیت روزمره. README منبع می‌گوید شرکت‌کنندگان سالمند فقط فعالیت روزمره را اجرا کردند، به‌جز SE06 که متخصص جودو بود و سقوط‌ها را هم شبیه‌سازی کرد؛ بنابراین این اعتبارسنجی، عملکرد سقوط در سالمندان ناتوان را ثابت نمی‌کند. پنج فایل \`D17_SE15_R01..R05.txt\` در پوشهٔ \`SA15\` قرار دارند؛ تبدیل‌گر شناسهٔ پوشه را بر شناسهٔ داخل نام فایل مقدم می‌گیرد. این اختلاف و قاعده در راهنمای داده ثبت شده‌اند.

## آموزش و اعتبارسنجی

- ردیف‌های ویژگی: ${rowCount}
- برچسب داده: \`${model.datasetKind}\`
- KNN (k=${model.knn.k}): دقت ${pct(knn.accuracy)}، precision ${pct(knn.precision)}، recall ${pct(knn.recall)}، F1 ${pct(knn.f1)}
- Linear SVM: دقت ${pct(svm.accuracy)}، precision ${pct(svm.precision)}، recall ${pct(svm.recall)}، F1 ${pct(svm.f1)}
- قاعدهٔ ترکیبی: دقت ${pct(ensemble.accuracy)}، precision ${pct(ensemble.precision)}، recall ${pct(ensemble.recall)}، F1 ${pct(ensemble.f1)}
- زمان آموزش: ${model.trainedAt}

اعتبارسنجی ${model.training.foldStrategy} است؛ مقیاس‌بندی درون هر fold برازش می‌شود و تنظیم ابرپارامتر در foldهای داخلی انجام می‌شود. جاروب ۴۸ ترکیب threshold از امتیازهای out-of-fold در \`docs/evaluation/fall-rule-threshold-sweep.csv\` نوشته شده است. این نتایج جای ارزیابی روی افراد/پیاده‌روی مستقل و دادهٔ واقعی محصول را نمی‌گیرند. سقوط‌های SisFall در آزمایش شبیه‌سازی شده‌اند و سقوط ناخواسته در محیط واقعی نیستند.
`;
  fs.mkdirSync(path.dirname(REPORT_PATH), { recursive: true });
  fs.writeFileSync(REPORT_PATH, report, 'utf8');
}

function main() {
  const converted = PREPARED_CSV ? null : path.join(os.tmpdir(), `safestep-sisfall-${randomUUID()}.csv`);
  let source;
  try {
    if (converted) {
      if (!fs.existsSync(RAW)) {
        throw new Error(`SisFall source data not found. Add raw recordings under ${RAW} or set SISFALL_FEATURE_CSV to a prepared feature CSV.`);
      }
      convertIfPresent(converted);
    }
    source = fs.readFileSync(converted ?? DATA_CSV, 'utf8');
  } finally {
    if (converted && fs.existsSync(converted)) fs.unlinkSync(converted);
  }
  if (source.includes('# SYNTHETIC')) {
    throw new Error(`Refusing to train the SisFall model from synthetic data: ${DATA_CSV}`);
  }
  const rows = parseCsv(source);
  if (rows.length === 0) throw new Error(`No valid labeled feature rows found in ${DATA_CSV}`);
  if (rows.some((row) => !row.subjectId || !row.recordingId)) {
      throw new Error('SisFall rows must include subject_id and recording_id columns. Regenerate with convert_sisfall.js or provide a 17-column grouped feature CSV.');
  }

  let scores;
  const model = trainFromRows(rows, { onOuterScores: (outerScores) => { scores = outerScores; } });
  model.datasetKind = 'sisfall-public-simulated-falls';
  fs.writeFileSync(MODEL_PATH, JSON.stringify(model), 'utf8');

  fs.mkdirSync(path.dirname(SWEEP_PATH), { recursive: true });
  fs.writeFileSync(SWEEP_PATH, thresholdSweepCsv(model.thresholdSweep), 'utf8');
  fs.writeFileSync(OOF_PATH, outOfFoldCsv(scores), 'utf8');
  writeReport(model, rows.length);
  process.stdout.write(`Trained SisFall model from ${rows.length} rows; threshold sweep: ${SWEEP_PATH}\n`);
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
