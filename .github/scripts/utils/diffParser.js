// utils/diffParser.js
// Wrapper around parse-diff that returns a normalized list of changed
// files with their content lines and the line numbers that the PR
// actually changed (so we can post inline comments on those lines only).

const parseDiff = require('parse-diff');

function parseUnifiedDiff(diffText) {
  const files = parseDiff(diffText);
  return files.map(f => {
    const changedLines = new Set();
    for (const chunk of f.chunks) {
      for (const change of chunk.changes) {
        if (change.type === 'add' || change.type === 'normal') {
          if (change.ln) changedLines.add(change.ln);
          if (change.ln2) changedLines.add(change.ln2);
        }
      }
    }
    return {
      path: f.to || f.from,
      from: f.from,
      to: f.to,
      deleted: f.deleted === true,
      added: f.new === true,
      chunks: f.chunks,
      changedLines: [...changedLines].sort((a, b) => a - b),
    };
  });
}

module.exports = { parseUnifiedDiff };
