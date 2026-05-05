#!/usr/bin/env node
/**
 * GenerateSfdxCommand.js
 *
 * Reads delta/package/package.xml, finds Apex classes that changed,
 * and resolves which test classes cover them. Writes the result to
 * sfCommandTests.txt (one test class per line).
 *
 * Heuristics:
 *   1. If a class FooTest.cls or TestFoo.cls exists for class Foo, use it.
 *   2. Always include any test class whose name matches the changed class name.
 *   3. If no targeted tests can be found, the file is left empty — the
 *      validate step then falls back to RunLocalTests for safety.
 */

const fs = require('fs');
const path = require('path');

const PACKAGE_XML = 'delta/package/package.xml';
const FORCE_APP = 'force-app/main/default/classes';
const OUT_FILE = 'sfCommandTests.txt';

function readChangedApexClasses() {
  if (!fs.existsSync(PACKAGE_XML)) return [];
  const xml = fs.readFileSync(PACKAGE_XML, 'utf8');

  // Naive extraction — fine for the simple package.xml that sgd produces.
  const blocks = xml.split(/<types>/).slice(1);
  const classes = [];
  for (const block of blocks) {
    const nameMatch = block.match(/<name>([^<]+)<\/name>/);
    if (!nameMatch || nameMatch[1] !== 'ApexClass') continue;
    const memberMatches = [...block.matchAll(/<members>([^<]+)<\/members>/g)];
    memberMatches.forEach(m => classes.push(m[1]));
  }
  return classes;
}

function isTestClass(filePath) {
  if (!fs.existsSync(filePath)) return false;
  const content = fs.readFileSync(filePath, 'utf8');
  return /@\s*isTest/i.test(content);
}

function findRelatedTests(changedClasses) {
  const tests = new Set();
  if (!fs.existsSync(FORCE_APP)) return tests;

  const allClassFiles = fs
    .readdirSync(FORCE_APP)
    .filter(f => f.endsWith('.cls'));

  for (const cls of changedClasses) {
    // 1. The class itself is a test class — include it
    const ownPath = path.join(FORCE_APP, `${cls}.cls`);
    if (isTestClass(ownPath)) {
      tests.add(cls);
      continue;
    }
    // 2. Look for FooTest, TestFoo, Foo_Test patterns
    const candidates = [
      `${cls}Test`,
      `Test${cls}`,
      `${cls}_Test`,
      `${cls}Tests`,
    ];
    for (const cand of candidates) {
      if (allClassFiles.includes(`${cand}.cls`)) {
        const candPath = path.join(FORCE_APP, `${cand}.cls`);
        if (isTestClass(candPath)) tests.add(cand);
      }
    }
    // 3. Any test class that mentions this class name
    for (const f of allClassFiles) {
      if (!f.endsWith('.cls')) continue;
      const full = path.join(FORCE_APP, f);
      if (!isTestClass(full)) continue;
      const content = fs.readFileSync(full, 'utf8');
      const re = new RegExp(`\\b${cls}\\b`);
      if (re.test(content)) tests.add(f.replace(/\.cls$/, ''));
    }
  }
  return tests;
}

function main() {
  const changed = readChangedApexClasses();
  console.log(`Changed Apex classes: ${changed.join(', ') || '(none)'}`);
  const tests = findRelatedTests(changed);
  const lines = [...tests].sort();
  fs.writeFileSync(OUT_FILE, lines.join('\n'));
  console.log(`Resolved ${lines.length} test class(es): ${lines.join(', ') || '(none)'}`);
  if (lines.length === 0) {
    console.warn('No targeted tests found. Validate will use the configured test_level.');
  }
}

main();
