import MarkdownIt from 'markdown-it';

// `html: true` so an HTML block counts as a block, as it does for the
// CommonMark renderers on the server.
const md = new MarkdownIt({ html: true });

// A markdown hard break written as two trailing spaces. Unlike `\` + newline,
// an authored trailing backslash (`C:\`) cannot escape it, and the channels
// that send the raw text (API, TikTok) show nothing for it.
export const HARD_BREAK = '  \n';

const blockTypes = tokens =>
  tokens
    .filter(token => token.level === 0 && token.nesting >= 0)
    .map(token => token.type);

const hardBreakCount = tokens =>
  tokens
    .filter(token => token.type === 'inline')
    .reduce(
      (count, token) =>
        count +
        token.children.filter(child => child.type === 'hardbreak').length,
      0
    );

// Joins two texts on adjacent lines. A lone newline is a markdown soft break,
// which the Email and Line renderers turn into a space, so a hard break joins
// them when the last block above and the first below are paragraphs and the
// joined text gains exactly that hard break. Anything that changes the
// structure at the seam (a `===` turning the paragraph into a heading, a
// delimiter row turning it into a table, a backslash before the break) loses
// it, and a list, quote or table above would swallow the next line, so those
// need a blank line to stay apart.
export const lineBreakBetween = (upper, lower) => {
  const [upperTokens, lowerTokens, joinedTokens] = [
    upper,
    lower,
    `${upper}${HARD_BREAK}${lower}`,
  ].map(text => md.parse(text, {}));
  const joinsParagraphs =
    blockTypes(upperTokens).at(-1) === 'paragraph_open' &&
    blockTypes(lowerTokens)[0] === 'paragraph_open' &&
    hardBreakCount(joinedTokens) ===
      hardBreakCount(upperTokens) + hardBreakCount(lowerTokens) + 1;
  return joinsParagraphs ? HARD_BREAK : '\n\n';
};
