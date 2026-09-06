import fs from 'node:fs';
import path from 'node:path';

const sr = 22050;
const n = Math.floor(sr * 0.35);
const hz = 880;
const data = Buffer.alloc(44 + n * 2);
data.write('RIFF', 0);
data.writeUInt32LE(36 + n * 2, 4);
data.write('WAVE', 8);
data.write('fmt ', 12);
data.writeUInt32LE(16, 16);
data.writeUInt16LE(1, 20);
data.writeUInt16LE(1, 22);
data.writeUInt32LE(sr, 24);
data.writeUInt32LE(sr * 2, 28);
data.writeUInt16LE(2, 32);
data.writeUInt16LE(16, 34);
data.write('data', 36);
data.writeUInt32LE(n * 2, 40);
for (let i = 0; i < n; i += 1) {
  const env = Math.min(1, i / 200, (n - i) / 400);
  const s = Math.sin((2 * Math.PI * hz * i) / sr) * 0.6 * env;
  data.writeInt16LE(Math.max(-32767, Math.min(32767, Math.round(s * 32767))), 44 + i * 2);
}
const out = path.resolve('android/app/src/main/res/raw/sos_alert.wav');
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, data);
process.stdout.write(`${out}\n`);
