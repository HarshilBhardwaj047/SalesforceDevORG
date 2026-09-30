// utils/braces.js
// Depth-aware brace matching. Several rules previously extracted a block
// body with a lazy regex like `\{([\s\S]*?)\}`, which stops at the FIRST
// closing brace -- wrong as soon as the block contains any nested `{...}`
// (an if-statement, inner loop, etc). This walks the actual brace depth.

// `openIndex` must point at a '{' character. Returns the index of its
// matching '}', or -1 if the braces in `content` from that point on are
// unbalanced.
function findMatchingBrace(content, openIndex) {
  let depth = 0;
  for (let i = openIndex; i < content.length; i++) {
    if (content[i] === '{') depth++;
    else if (content[i] === '}') {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

module.exports = { findMatchingBrace };
