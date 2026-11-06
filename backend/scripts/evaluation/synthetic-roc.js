/** Parse only explicitly marked synthetic data; reject a partial or foreign schema. */
export function parseSyntheticCsv(source) {
  const lines = source.trim().split(/\r?\n/);
  const expected = ['label', ...Array.from({ length: 14 }, (_, i) => `f${i + 1}`)].join(',');
  if (lines[0] !== '# SYNTHETIC' || lines[1] !== expected || lines.length < 3) return null;
  const rows = [];
  for (const line of lines.slice(2)) {
    const cells = line.split(',');
    if (cells.length !== 15 || cells.some((cell) => !cell.trim())) return null;
    const [label, ...features] = cells.map(Number);
    if (![0, 1].includes(label) || features.some((n) => !Number.isFinite(n))) return null;
    rows.push({ label, features });
  }
  return rows.some((r) => r.label === 0) && rows.some((r) => r.label === 1) ? rows : null;
}
