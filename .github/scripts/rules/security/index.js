// rules/security/index.js

function check(filePath, content) {
  const findings = [];

  // SF-SEC-001: `global` keyword on Apex class (overuse risk)
  if (filePath.endsWith('.cls')) {
    const m = content.match(/^\s*global\s+(?:with\s+sharing\s+|without\s+sharing\s+|inherited\s+sharing\s+)?class\s+/m);
    if (m) {
      const startLine = content.slice(0, m.index).split('\n').length + 1;
      findings.push({
        ruleId: 'SF-SEC-001',
        severity: 'medium',
        path: filePath,
        startLine,
        message: '`global` access modifier on Apex class. Use `public` unless this class is genuinely needed in a managed package API.',
      });
    }
  }

  // SF-SEC-002: Class without `with sharing` declaration
  if (filePath.endsWith('.cls') && !/@\s*isTest/i.test(content)) {
    const classDecl = content.match(/^\s*(public|global|private)\s+class\s+(\w+)/m);
    if (classDecl) {
      const hasSharing = /\b(with sharing|without sharing|inherited sharing)\b/i.test(content.slice(0, classDecl.index + 200));
      if (!hasSharing) {
        const startLine = content.slice(0, classDecl.index).split('\n').length + 1;
        findings.push({
          ruleId: 'SF-SEC-002',
          severity: 'medium',
          path: filePath,
          startLine,
          message: `Class ${classDecl[2]} does not declare a sharing model. Add 'with sharing', 'without sharing', or 'inherited sharing' explicitly.`,
        });
      }
    }
  }

  return findings;
}

module.exports = { check };
