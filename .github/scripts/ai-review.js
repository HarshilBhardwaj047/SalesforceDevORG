// ai-review.js
// Claude Sonnet review layer. Read-only — never suggests code changes.
// Five cost guards (in order of efficiency):
//   1. Skip non-logic PRs (XML-only metadata changes)
//   2. Diff-only for non-logic files
//   3. Hard input cap (~12,500 tokens — context files dropped to fit)
//   4. Output cap (max_tokens: 2048 — ~15 findings)
//   5. Context file limit (max 8 related repo files)

const fs = require('fs');
const path = require('path');
const Anthropic = require('@anthropic-ai/sdk');

const MODEL = 'claude-sonnet-4-5';
const MAX_INPUT_TOKENS = 12500;
const MAX_CONTEXT_FILES = 8;
const MAX_OUTPUT_TOKENS = 2048;

const LOGIC_EXTENSIONS = ['.cls', '.trigger', '.js'];
const METADATA_EXTENSIONS = ['.xml', '.flow-meta.xml', '.object-meta.xml', '.field-meta.xml', '.permissionset-meta.xml'];

function isLogicFile(p) {
  if (p.includes('/lwc/') && p.endsWith('.js') && !p.includes('__tests__')) return true;
  return LOGIC_EXTENSIONS.some(ext => p.endsWith(ext)) && !p.endsWith('.xml');
}

function isMetadataFile(p) {
  return METADATA_EXTENSIONS.some(ext => p.endsWith(ext));
}

// crude token estimate: 4 chars ≈ 1 token
function estimateTokens(s) {
  return Math.ceil((s || '').length / 4);
}

function findRelatedFiles(changedFiles, repoRoot) {
  // For each changed Apex/Trigger/LWC file, find related files in the repo:
  //  - Other triggers on the same object
  //  - The object metadata file
  //  - Test classes referencing the changed class
  const related = new Set();
  for (const f of changedFiles) {
    if (f.path.endsWith('.trigger')) {
      const objectMatch = f.path.match(/\/triggers\/([A-Za-z0-9_]+)\.trigger$/);
      if (objectMatch) {
        // find object name from trigger declaration
        const content = safeRead(path.join(repoRoot, f.path));
        const onMatch = content.match(/trigger\s+\w+\s+on\s+(\w+)/i);
        if (onMatch) {
          const obj = onMatch[1];
          const triggerDir = path.join(repoRoot, 'force-app/main/default/triggers');
          if (fs.existsSync(triggerDir)) {
            for (const tf of fs.readdirSync(triggerDir)) {
              if (tf.endsWith('.trigger') && tf !== `${objectMatch[1]}.trigger`) {
                const tcontent = safeRead(path.join(triggerDir, tf));
                if (new RegExp(`\\bon\\s+${obj}\\b`, 'i').test(tcontent)) {
                  related.add(`force-app/main/default/triggers/${tf}`);
                }
              }
            }
          }
          const objMeta = `force-app/main/default/objects/${obj}/${obj}.object-meta.xml`;
          if (fs.existsSync(path.join(repoRoot, objMeta))) related.add(objMeta);
        }
      }
    }
    if (f.path.endsWith('.cls')) {
      const className = path.basename(f.path, '.cls');
      const classDir = path.join(repoRoot, 'force-app/main/default/classes');
      if (fs.existsSync(classDir)) {
        for (const cf of fs.readdirSync(classDir)) {
          if (cf === `${className}.cls`) continue;
          if (cf.endsWith('.cls')) {
            const ccontent = safeRead(path.join(classDir, cf));
            if (new RegExp(`\\b${className}\\b`).test(ccontent)) {
              related.add(`force-app/main/default/classes/${cf}`);
            }
          }
        }
      }
    }
  }
  return [...related].slice(0, MAX_CONTEXT_FILES);
}

function safeRead(p) {
  try { return fs.readFileSync(p, 'utf8'); } catch { return ''; }
}

async function runAiReview({ changedFiles, repoRoot }) {
  if (!process.env.ANTHROPIC_API_KEY) {
    console.log('ANTHROPIC_API_KEY not set — skipping AI review layer.');
    return [];
  }

  // Guard 1: skip non-logic PRs
  const logicFiles = changedFiles.filter(f => isLogicFile(f.path) && !f.deleted);
  if (logicFiles.length === 0) {
    console.log('AI review: no logic files changed — skipping (cost guard 1).');
    return [];
  }

  // Guard 5: collect at most MAX_CONTEXT_FILES related files
  const relatedPaths = findRelatedFiles(logicFiles, repoRoot);

  // Build prompt content blocks
  const logicBlocks = logicFiles.map(f => {
    const content = safeRead(path.join(repoRoot, f.path));
    return `### CHANGED FILE: ${f.path}\n\`\`\`\n${content}\n\`\`\``;
  });

  // Guard 2: diff-only for metadata files
  const metadataDiffBlocks = changedFiles
    .filter(f => isMetadataFile(f.path) && !f.deleted)
    .map(f => `### METADATA DIFF: ${f.path}\n${formatDiff(f)}`);

  const contextBlocks = relatedPaths.map(p => {
    const content = safeRead(path.join(repoRoot, p));
    // truncate context files to first 200 lines to be safe
    const truncated = content.split('\n').slice(0, 200).join('\n');
    return `### CONTEXT FILE: ${p}\n\`\`\`\n${truncated}\n\`\`\``;
  });

  // Guard 3: trim to fit input cap
  let blocks = [...logicBlocks, ...metadataDiffBlocks, ...contextBlocks];
  let totalTokens = blocks.reduce((s, b) => s + estimateTokens(b), 0);
  while (totalTokens > MAX_INPUT_TOKENS && blocks.length > logicFiles.length) {
    blocks.pop();  // drop context files first (they are at the tail)
    totalTokens = blocks.reduce((s, b) => s + estimateTokens(b), 0);
  }

  console.log(`AI review: ${logicFiles.length} logic file(s), ${contextBlocks.length} context file(s), ~${totalTokens} input tokens estimated`);

  const systemPrompt = `You are a senior Salesforce code reviewer. Your sole purpose is to identify and describe issues in pull requests — you NEVER write, generate, or suggest code changes. You are read-only.

Focus on issues that static pattern-matching CANNOT detect:
- CRUD/FLS enforcement gaps in @AuraEnabled methods
- Sharing model violations and 'without sharing' misuse
- Mixed DML across setup and non-setup objects
- Async (Future / Queueable / Batch) anti-patterns
- Trigger / record-triggered Flow dual-automation conflicts
- Cross-file impact: field renames breaking other metadata, method signature changes breaking callers
- Validation rules breaking existing test data
- Null-unsafe Get Records access in Flows
- LWC stale reactive state and missing wire error handling

Return ONLY a JSON array of findings. NO prose, NO code blocks, NO commentary outside the JSON. Each finding MUST follow this exact schema:

{
  "ruleId": "SF-AI-XXX",
  "severity": "low" | "medium" | "high",
  "path": "<repo path>",
  "startLine": <number>,
  "message": "<concise description of the issue>"
}

Use ruleId prefixes:
- SF-AI-CRUD-* for CRUD/FLS issues
- SF-AI-SHARING-* for sharing violations
- SF-AI-DML-* for DML / async issues
- SF-AI-IMPACT-* for cross-file impact
- SF-AI-FLOW-* for flow-related issues
- SF-AI-LWC-* for LWC-only issues

If you find no issues, return [].`;

  const userPrompt = blocks.join('\n\n');

  const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  let response;
  try {
    response = await client.messages.create({
      model: MODEL,
      max_tokens: MAX_OUTPUT_TOKENS,
      system: systemPrompt,
      messages: [{ role: 'user', content: userPrompt }],
    });
  } catch (err) {
    console.error(`AI review: API call failed — ${err.message}`);
    return [];
  }

  console.log(`AI review: tokens used — input: ${response.usage?.input_tokens}, output: ${response.usage?.output_tokens}, cache_read: ${response.usage?.cache_read_input_tokens || 0}, cache_write: ${response.usage?.cache_creation_input_tokens || 0}`);

  const text = response.content.filter(c => c.type === 'text').map(c => c.text).join('');

  let findings = [];
  try {
    // The model is instructed to return JSON only, but be defensive.
    const jsonMatch = text.match(/\[[\s\S]*\]/);
    findings = jsonMatch ? JSON.parse(jsonMatch[0]) : [];
  } catch (err) {
    console.error(`AI review: failed to parse response — ${err.message}`);
    console.error(`Raw response: ${text.slice(0, 500)}`);
    return [];
  }

  // Validate shape
  return findings.filter(f =>
    f && f.ruleId && f.severity && f.path && Number.isInteger(f.startLine) && f.message
  );
}

function formatDiff(file) {
  const lines = [];
  for (const chunk of file.chunks || []) {
    for (const change of chunk.changes || []) {
      const prefix = change.type === 'add' ? '+ ' : change.type === 'del' ? '- ' : '  ';
      lines.push(prefix + (change.content || ''));
    }
  }
  return lines.slice(0, 100).join('\n');
}

module.exports = { runAiReview };
