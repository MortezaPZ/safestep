import { expect, it } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';

it('includes the classifier runtime import in the image layout', () => {
  const dockerfile = fs.readFileSync('Dockerfile', 'utf8');
  expect(dockerfile).toContain('COPY backend/scripts/falls/generate_synthetic.js ./scripts/falls/generate_synthetic.js');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'safestep-image-import-'));
  const folders = ['src', 'src/services', 'src/services/fallDetection', 'scripts', 'scripts/falls'];
  const copies = [
    ['src/services/fallDetection/classifier.js', 'src/services/fallDetection/classifier.js'],
    ['src/services/fallDetection/features.js', 'src/services/fallDetection/features.js'],
    ['scripts/falls/generate_synthetic.js', 'scripts/falls/generate_synthetic.js'],
  ];
  try {
    for (const folder of folders) fs.mkdirSync(path.join(root, folder));
    fs.writeFileSync(path.join(root, 'package.json'), '{"type":"module"}');
    for (const [source, target] of copies.slice(0, 2)) fs.copyFileSync(source, path.join(root, target));
    const url = pathToFileURL(path.join(root, 'src/services/fallDetection/classifier.js')).href;
    const runImport = () => spawnSync(process.execPath, ['--input-type=module', '-e', `await import(${JSON.stringify(url)})`],
      { encoding: 'utf8', timeout: 15000 });
    const before = runImport();
    expect(before.status).not.toBe(0);
    expect(before.stderr).toContain('generate_synthetic.js');
    fs.copyFileSync(copies[2][0], path.join(root, copies[2][1]));
    const child = runImport();
    expect(child.status, child.stderr).toBe(0);
  } finally {
    for (const [, target] of copies) {
      const file = path.join(root, target);
      if (fs.existsSync(file)) fs.unlinkSync(file);
    }
    const manifest = path.join(root, 'package.json');
    if (fs.existsSync(manifest)) fs.unlinkSync(manifest);
    for (const folder of [...folders].reverse()) {
      const dir = path.join(root, folder);
      if (fs.existsSync(dir)) fs.rmdirSync(dir);
    }
    fs.rmdirSync(root);
  }
});
