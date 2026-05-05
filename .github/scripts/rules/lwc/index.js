// rules/lwc/index.js

function check(filePath, content) {
  // Apply only to .js files in lwc/, but skip __tests__ files
  if (!filePath.includes('/lwc/') || !filePath.endsWith('.js')) return [];
  if (filePath.includes('__tests__')) return [];
  const findings = [];
  const lines = content.split('\n');

  // SF-LWC-001: Hardcoded URLs (https/http literals)
  for (let i = 0; i < lines.length; i++) {
    if (/['"`]https?:\/\/[^'"`]+['"`]/.test(lines[i]) && !/localhost|example\.com/.test(lines[i])) {
      findings.push({
        ruleId: 'SF-LWC-001',
        severity: 'medium',
        path: filePath,
        startLine: i + 1,
        message: 'Hardcoded URL in LWC. Use a custom label, custom setting, or static resource URL.',
      });
    }
  }

  // SF-LWC-002: Imperative Apex calls without .catch
  // Strategy: find each `.then(` and walk forward tracking paren depth.
  // The chain ends when paren depth drops back to zero. If a `.catch(`
  // appears after the closing paren but before a non-method-call character,
  // the chain has error handling.
  {
    let idx = 0;
    while ((idx = content.indexOf('.then(', idx)) !== -1) {
      // Walk from the `(` after `.then` and find its matching `)`
      let depth = 0;
      let i = idx + 5;  // position of '('
      let chainEnd = -1;
      for (; i < content.length; i++) {
        const ch = content[i];
        if (ch === '(') depth++;
        else if (ch === ')') {
          depth--;
          if (depth === 0) { chainEnd = i + 1; break; }
        }
      }
      if (chainEnd === -1) { idx += 6; continue; }
      // Look at what follows the closing paren — skip whitespace and look for `.catch(`
      const after = content.slice(chainEnd, chainEnd + 200);
      const trimmed = after.replace(/^\s+/, '');
      if (!trimmed.startsWith('.catch(') && !trimmed.startsWith('.finally(')) {
        const startLine = content.slice(0, idx).split('\n').length;
        findings.push({
          ruleId: 'SF-LWC-002',
          severity: 'medium',
          path: filePath,
          startLine,
          message: 'Imperative Apex call has .then but no .catch. Add error handling.',
        });
      }
      idx = chainEnd;
    }
  }

  // SF-LWC-003: Direct DOM manipulation
  for (let i = 0; i < lines.length; i++) {
    if (/document\.(getElementById|querySelector|querySelectorAll)/.test(lines[i])) {
      findings.push({
        ruleId: 'SF-LWC-003',
        severity: 'high',
        path: filePath,
        startLine: i + 1,
        message: 'Direct DOM access via `document` is forbidden in LWC. Use template.querySelector or @api/@track properties.',
      });
    }
  }

  return findings;
}

module.exports = { check };
