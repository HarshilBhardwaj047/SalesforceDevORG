// rules/apex/index.js
// Static, deterministic Apex rules. Each rule is a pure function:
//   (file, content) => Finding[]
// Finding shape: { ruleId, severity, path, startLine, message, suggestion }

const { findSoqlStartLines } = require('../../utils/soql');
const { findLoopBodyLines } = require('../../utils/loops');
const { findMatchingBrace } = require('../../utils/braces');

const RULES = [];

function rule(ruleId, severity, fn) {
  RULES.push({ ruleId, severity, fn });
}

// SF-APEX-001: SOQL inside for/while loop
rule('SF-APEX-001', 'high', (path, content) => {
  const findings = [];
  const lines = content.split('\n');
  const soqlStarts = new Set(findSoqlStartLines(lines));
  const loopLines = findLoopBodyLines(lines);
  for (const i of soqlStarts) {
    if (loopLines.has(i)) {
      findings.push({
        startLine: i + 1,
        message: 'SOQL query inside a loop. Move the query outside the loop and process results in bulk.',
        suggestion: 'Query before the loop, then iterate over the result set.',
      });
    }
  }
  return findings;
});

// SF-APEX-002: DML inside for/while loop
rule('SF-APEX-002', 'high', (path, content) => {
  const findings = [];
  const lines = content.split('\n');
  const loopLines = findLoopBodyLines(lines);
  for (let i = 0; i < lines.length; i++) {
    if (loopLines.has(i) && /^\s*(insert|update|upsert|delete|undelete|merge)\s+/i.test(lines[i])) {
      findings.push({
        startLine: i + 1,
        message: 'DML inside a loop. Collect records into a list and DML once after the loop.',
        suggestion: 'List<SObject> toUpdate = new List<SObject>(); for(...) { toUpdate.add(...); } update toUpdate;',
      });
    }
  }
  return findings;
});

// SF-APEX-003: Hardcoded record IDs (15 or 18 char)
// Salesforce key prefixes vary per object (standard AND custom), so
// requiring a literal "00" prefix (the old regex) misses the vast
// majority of custom-object IDs. Match the general shape instead --
// exactly 15 or 18 alphanumerics containing both a letter and a digit,
// which real IDs always do but incidental 15/18-char word-like strings
// usually don't.
rule('SF-APEX-003', 'medium', (path, content) => {
  const findings = [];
  const lines = content.split('\n');
  const idRe = /['"]([a-zA-Z0-9]{15}|[a-zA-Z0-9]{18})['"]/g;
  for (let i = 0; i < lines.length; i++) {
    let m;
    idRe.lastIndex = 0;
    while ((m = idRe.exec(lines[i])) !== null) {
      const candidate = m[1];
      if (/[0-9]/.test(candidate) && /[a-zA-Z]/.test(candidate)) {
        findings.push({
          startLine: i + 1,
          message: 'Hardcoded Salesforce record ID detected. Use Custom Metadata, Custom Settings, or Schema describe instead.',
          suggestion: 'Store the ID in a Custom Metadata Type or Custom Setting field and read it at runtime instead of hardcoding it.',
        });
      }
    }
  }
  return findings;
});

// SF-APEX-004: Bare `catch (...)` whose body only logs and (optionally) returns
rule('SF-APEX-004', 'medium', (path, content) => {
  const findings = [];
  const headerRe = /catch\s*\(\s*\w*Exception\s+\w+\s*\)\s*\{/g;
  let m;
  while ((m = headerRe.exec(content)) !== null) {
    const openIdx = m.index + m[0].length - 1;
    const closeIdx = findMatchingBrace(content, openIdx);
    if (closeIdx === -1) break;
    const body = content.slice(openIdx + 1, closeIdx).trim();
    headerRe.lastIndex = closeIdx + 1;
    if (!body) continue;
    const statements = body
      .split(';')
      .map(s => s.trim())
      .filter(Boolean);
    const onlyDebugsAndReturns = statements.every(s =>
      /^System\.debug\b/i.test(s) || /^return\b/.test(s)
    );
    const hasRethrowOrAddError = /\b(throw|addError)\b/i.test(body);
    if (onlyDebugsAndReturns && !hasRethrowOrAddError) {
      const startLine = content.slice(0, m.index).split('\n').length;
      findings.push({
        startLine,
        message: 'Catch block silently swallows exception (only logs and returns). Re-throw, call addError, or surface the error to the caller.',
        suggestion: 'Add `throw ex;` to propagate it, call `ex.addError()` in a trigger context, or return an error result the caller can act on.',
      });
    }
  }
  return findings;
});

// SF-APEX-005: SOQL without WITH USER_MODE / WITH SECURITY_ENFORCED in classes that touch shared data
rule('SF-APEX-005', 'medium', (path, content) => {
  const findings = [];
  // Skip test classes
  if (/@\s*isTest/i.test(content)) return findings;
  const lines = content.split('\n');
  for (const i of findSoqlStartLines(lines)) {
    const region = lines.slice(i, Math.min(i + 6, lines.length)).join(' ');
    if (!/WITH\s+(USER_MODE|SECURITY_ENFORCED|SYSTEM_MODE)/i.test(region)) {
      findings.push({
        startLine: i + 1,
        message: 'SOQL query does not declare a security mode. Add WITH USER_MODE (or WITH SECURITY_ENFORCED) to enforce CRUD/FLS.',
        suggestion: 'Append WITH USER_MODE (API 57.0+) or WITH SECURITY_ENFORCED to the query.',
      });
    }
  }
  return findings;
});

// SF-APEX-006: @AuraEnabled DML method without try/catch
// (cacheable=true read methods are exempt -- exceptions there are framework-handled)
rule('SF-APEX-006', 'medium', (path, content) => {
  const findings = [];
  const headerRe = /@\s*AuraEnabled([^{]*?)(public|global)\s+static\s+\w[\w<>,\[\]\s]*\s+(\w+)\s*\([^)]*\)\s*\{/g;
  let m;
  while ((m = headerRe.exec(content)) !== null) {
    const annotation = m[1];
    const methodName = m[3];
    const openIdx = m.index + m[0].length - 1;
    const closeIdx = findMatchingBrace(content, openIdx);
    if (closeIdx === -1) break;
    const body = content.slice(openIdx + 1, closeIdx);
    headerRe.lastIndex = closeIdx + 1;

    if (/cacheable\s*=\s*true/i.test(annotation)) continue;
    if (!/\b(insert|update|upsert|delete|undelete|merge|Database\.\w+)\b/.test(body)) continue;
    if (!/try\s*\{/i.test(body)) {
      const startLine = content.slice(0, m.index).split('\n').length;
      findings.push({
        startLine,
        message: `@AuraEnabled DML method ${methodName} has no try/catch. Wrap in try/catch and throw AuraHandledException with a friendly message.`,
        suggestion: 'try { ... } catch (Exception e) { throw new AuraHandledException(e.getMessage()); }',
      });
    }
  }
  return findings;
});

function check(filePath, content) {
  if (!filePath.endsWith('.cls')) return [];
  const findings = [];
  for (const r of RULES) {
    for (const f of r.fn(filePath, content)) {
      findings.push({
        ruleId: r.ruleId,
        severity: r.severity,
        path: filePath,
        ...f,
      });
    }
  }
  return findings;
}

module.exports = { check };
