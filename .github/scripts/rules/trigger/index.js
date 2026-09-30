// rules/trigger/index.js

const { findSoqlStartLines } = require('../../utils/soql');

function check(filePath, content) {
  if (!filePath.endsWith('.trigger')) return [];
  const findings = [];
  const lines = content.split('\n');

  // SF-TRIG-001: Logic directly in trigger body (not delegated to handler)
  // Heuristic: more than ~15 non-comment lines suggests logic in the trigger.
  // Strip block comments first -- a large `/* ... */` header (license
  // banner, doc block) whose interior lines don't start with `//`/`*`
  // was previously counted as code, inflating the line count.
  const withoutBlockComments = content.replace(/\/\*[\s\S]*?\*\//g, '');
  const codeLines = withoutBlockComments
    .split('\n')
    .filter(l => l.trim() && !l.trim().startsWith('//') && !l.trim().startsWith('*'));
  if (codeLines.length > 15) {
    findings.push({
      ruleId: 'SF-TRIG-001',
      severity: 'medium',
      path: filePath,
      startLine: 1,
      message: `Trigger body is ${codeLines.length} lines. Move logic into a handler class (e.g. AccountTriggerHandler) and call it from the trigger.`,
      suggestion: 'Extract the logic into a handler class (e.g. AccountTriggerHandler) and call it from the trigger body only.',
    });
  }

  // SF-TRIG-002: SOQL inside trigger body (almost always wrong)
  for (const i of findSoqlStartLines(lines)) {
    findings.push({
      ruleId: 'SF-TRIG-002',
      severity: 'high',
      path: filePath,
      startLine: i + 1,
      message: 'SOQL query inside a trigger. Move queries to the handler class for testability and bulkification.',
      suggestion: 'Move the query into the handler class and pass Trigger.new/Trigger.newMap in, so it can be unit tested and bulkified.',
    });
  }

  // SF-TRIG-003: DML inside trigger body
  for (let i = 0; i < lines.length; i++) {
    if (/^\s*(insert|update|upsert|delete|undelete|merge)\s+/i.test(lines[i])) {
      findings.push({
        ruleId: 'SF-TRIG-003',
        severity: 'high',
        path: filePath,
        startLine: i + 1,
        message: 'DML inside a trigger body. Move to handler class.',
        suggestion: 'Move the DML into the handler class, operating on the full Trigger.new/Trigger.old list rather than per-record.',
      });
    }
  }

  return findings;
}

module.exports = { check };
