// utils/loops.js
// Shared loop-body detection for the SOQL/DML-in-loop rules. The old
// implementation kept a flat `inLoop` counter that incremented on any
// `for(`/`while(` and decremented on ANY line containing `}` -- so a
// nested if-block closing before the loop itself did would pop the
// counter early and stop flagging lines still genuinely inside the loop.
//
// This tracks real brace depth and a stack of the depths at which loop
// bodies began, so nested non-loop blocks no longer cause false negatives.

// Returns a Set of 0-based line indices that are inside a for/while loop body.
function findLoopBodyLines(lines) {
  const inLoop = new Set();
  let depth = 0;
  const loopStack = [];
  let pendingLoopHeader = false;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (/\b(for|while)\s*\(/i.test(line)) pendingLoopHeader = true;

    const opens = (line.match(/\{/g) || []).length;
    const closes = (line.match(/\}/g) || []).length;

    for (let c = 0; c < opens; c++) {
      depth++;
      if (pendingLoopHeader) {
        // The next '{' seen after a loop header is that loop's own body,
        // even if it's on a later line than the header itself.
        loopStack.push(depth);
        pendingLoopHeader = false;
      }
    }
    depth -= closes;
    while (loopStack.length && depth < loopStack[loopStack.length - 1]) {
      loopStack.pop();
    }

    // A brace-less single-statement loop body (`for (...) doWork();`) has
    // no '{' to attach to -- drop the pending flag rather than letting it
    // leak forward and mis-attribute some later, unrelated block.
    if (pendingLoopHeader && opens === 0 && /;\s*$/.test(line.trim())) {
      pendingLoopHeader = false;
    }

    if (loopStack.length > 0) inLoop.add(i);
  }

  return inLoop;
}

module.exports = { findLoopBodyLines };
