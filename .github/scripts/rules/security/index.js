// rules/security/index.js

// Matches a top-level class declaration and captures whatever sits between
// the access modifier and the `class` keyword (abstract/virtual/sharing
// keywords in any order), so sharing detection can be scoped to THIS
// declaration instead of the old approach of scanning the whole preceding
// file content -- which false-negatived whenever an unrelated earlier
// comment, string, or sibling class happened to contain a sharing keyword.
const CLASS_DECL_RE = /^\s*(public|global|private)\s+((?:(?:abstract|virtual|with\s+sharing|without\s+sharing|inherited\s+sharing)\s+)*)class\s+(\w+)/im;

function check(filePath, content) {
  const findings = [];

  // SF-SEC-001: `global` keyword on Apex class (overuse risk)
  if (filePath.endsWith('.cls')) {
    const m = content.match(CLASS_DECL_RE);
    if (m && m[1].toLowerCase() === 'global') {
      const startLine = content.slice(0, m.index).split('\n').length + 1;
      findings.push({
        ruleId: 'SF-SEC-001',
        severity: 'medium',
        path: filePath,
        startLine,
        message: '`global` access modifier on Apex class. Use `public` unless this class is genuinely needed in a managed package API.',
        suggestion: 'Change `global` to `public` unless this class is part of a published managed-package API surface.',
      });
    }
  }

  // SF-SEC-002: Class without an explicit sharing declaration
  if (filePath.endsWith('.cls') && !/@\s*isTest/i.test(content)) {
    const classDecl = content.match(CLASS_DECL_RE);
    if (classDecl) {
      const hasSharing = /\b(with\s+sharing|without\s+sharing|inherited\s+sharing)\b/i.test(classDecl[2]);
      if (!hasSharing) {
        const startLine = content.slice(0, classDecl.index).split('\n').length + 1;
        findings.push({
          ruleId: 'SF-SEC-002',
          severity: 'medium',
          path: filePath,
          startLine,
          message: `Class ${classDecl[3]} does not declare a sharing model. Add 'with sharing', 'without sharing', or 'inherited sharing' explicitly.`,
          suggestion: `Add an explicit sharing keyword right after the access modifier, e.g. \`public with sharing class ${classDecl[3]}\`.`,
        });
      }
    }
  }

  return findings;
}

module.exports = { check };
