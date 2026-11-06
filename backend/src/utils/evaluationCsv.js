export function evaluationCsv(columns, rows) {
  const cell = (value) => {
    if (value === null || value === undefined) return '';
    if (value instanceof Date) return value.toISOString();
    let text = String(value);
    if (typeof value === 'string' && /^[\s]*[=+@\-\t\r]/.test(text)) text = "'" + text;
    return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
  };
  return [columns.join(','), ...rows.map((row) => columns.map((name) => cell(row[name])).join(','))].join('\r\n') + '\r\n';
}
