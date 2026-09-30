// utils/soql.js
// Shared SOQL-literal detection. A bare per-line `/\[\s*SELECT\s+/i` regex
// misses the common Apex convention of putting `[` on one line and `SELECT`
// on the next (used throughout this repo, e.g. AccountController.cls), so
// every rule that looks for `[SELECT ...]` blocks should use this instead.

// Returns the 0-based line indices where a SOQL query literal begins.
function findSoqlStartLines(lines, windowSize = 6) {
  const starts = [];
  for (let i = 0; i < lines.length; i++) {
    if (!lines[i].includes('[')) continue;
    const window = lines.slice(i, Math.min(i + windowSize, lines.length)).join(' ');
    if (/\[\s*SELECT\s+/i.test(window)) {
      starts.push(i);
    }
  }
  return starts;
}

module.exports = { findSoqlStartLines };
