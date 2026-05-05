// rules/apex/index.js
// Static, deterministic Apex rules. Each rule is a pure function:
//   (file, content) => Finding[]
// Finding shape: { ruleId, severity, path, startLine, message, suggestion }

const RULES = [];

function rule(ruleId, severity, fn) {
  RULES.push({ ruleId, severity, fn });
}

// SF-APEX-001: SOQL inside for/while loop
rule('SF-APEX-001', 'high', (path, content) => {
  const findings = [];
  const lines = content.split('\n');
  let depth = 0;
  let inLoop = 0;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    // crude loop detection
    if (/\b(for|while)\s*\(/i.test(line)) inLoop++;
    if (line.includes('}') && inLoop > 0) inLoop = Math.max(0, inLoop - 1);
    if (inLoop > 0 && /\[\s*SELECT\s+/i.test(line)) {
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
  let inLoop = 0;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (/\b(for|while)\s*\(/i.test(line)) inLoop++;
    if (line.includes('}') && inLoop > 0) inLoop = Math.max(0, inLoop - 1);
    if (inLoop > 0 && /^\s*(insert|update|upsert|delete|undelete|merge)\s+/i.test(line)) {
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
rule('SF-APEX-003', 'medium', (path, content) => {
  const findings = [];
  const lines = content.split('\n');
  for (let i = 0; i < lines.length; i++) {
    if (/'(00[0-9A-Za-z]{13}|00[0-9A-Za-z]{16})'/.test(lines[i])) {
      findings.push({
        startLine: i + 1,
        message: 'Hardcoded Salesforce record ID detected. Use Custom Metadata, Custom Settings, or Schema describe instead.',
      });
    }
  }
  return findings;
});

// SF-APEX-004: Bare `catch (...)` whose body only logs and (optionally) returns
rule('SF-APEX-004', 'medium', (path, content) => {
  const findings = [];
  const re = /catch\s*\(\s*\w*Exception\s+\w+\s*\)\s*\{([\s\S]*?)\}/g;
  let m;
  while ((m = re.exec(content)) !== null) {
    const body = m[1].trim();
    if (!body) continue;
    // Strip whitespace and check if the only statements are debugs and an optional return
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
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (/\[\s*SELECT\s+/i.test(line)) {
      // Look at the same line AND the next 3 lines for the close bracket region
      const region = lines.slice(i, Math.min(i + 6, lines.length)).join(' ');
      if (!/WITH\s+(USER_MODE|SECURITY_ENFORCED|SYSTEM_MODE)/i.test(region)) {
        findings.push({
          startLine: i + 1,
          message: 'SOQL query does not declare a security mode. Add WITH USER_MODE (or WITH SECURITY_ENFORCED) to enforce CRUD/FLS.',
        });
      }
    }
  }
  return findings;
});

// SF-APEX-006: @AuraEnabled DML method without try/catch
// (cacheable=true read methods are exempt — exceptions there are framework-handled)
rule('SF-APEX-006', 'medium', (path, content) => {
  const findings = [];
  const re = /@\s*AuraEnabled([^{]*?)(public|global)\s+static\s+\w[\w<>,\[\]\s]*\s+(\w+)\s*\([^)]*\)\s*\{([\s\S]*?)\n\s*\}/g;
  let m;
  while ((m = re.exec(content)) !== null) {
    const annotation = m[1];
    const body = m[4];
    // Skip if this is a cacheable read method
    if (/cacheable\s*=\s*true/i.test(annotation)) continue;
    // Skip if there's no DML in the body (read-only methods don't need try/catch)
    if (!/\b(insert|update|upsert|delete|undelete|merge|Database\.\w+)\b/.test(body)) continue;
    if (!/try\s*\{/i.test(body)) {
      const startLine = content.slice(0, m.index).split('\n').length;
      findings.push({
        startLine,
        message: `@AuraEnabled DML method ${m[3]} has no try/catch. Wrap in try/catch and throw AuraHandledException with a friendly message.`,
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
