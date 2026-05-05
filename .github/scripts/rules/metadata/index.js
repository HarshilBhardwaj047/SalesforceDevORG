// rules/metadata/index.js

function check(filePath, content) {
  const findings = [];

  // SF-META-001: API version below the team minimum (55.0)
  if (/-meta\.xml$/.test(filePath)) {
    const m = content.match(/<apiVersion>(\d+\.\d+)<\/apiVersion>/);
    if (m) {
      const v = parseFloat(m[1]);
      if (v < 55.0) {
        const startLine = content.slice(0, m.index).split('\n').length + 1;
        findings.push({
          ruleId: 'SF-META-001',
          severity: 'low',
          path: filePath,
          startLine,
          message: `API version ${m[1]} is below team minimum 55.0. Update to current platform release.`,
        });
      }
    }
  }

  // SF-META-002: Destructive change detected (file deleted)
  // The review.js entry point handles "deleted" files; this rule is invoked
  // on the placeholder to centralise the message.

  return findings;
}

function checkDeleted(filePath) {
  // Flag deletion of any .cls/.trigger/.flow-meta.xml as a destructive change requiring approval
  if (/\.(cls|trigger)$|\.flow-meta\.xml$|\.object-meta\.xml$|\.field-meta\.xml$/.test(filePath)) {
    return [{
      ruleId: 'SF-META-002',
      severity: 'high',
      path: filePath,
      startLine: 1,
      message: 'Destructive change: this file is being deleted. Confirm you have a destructiveChanges.xml entry and that no other code references it.',
    }];
  }
  return [];
}

module.exports = { check, checkDeleted };
