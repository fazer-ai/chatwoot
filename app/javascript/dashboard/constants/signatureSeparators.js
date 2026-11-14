// The message signature separators. InboxSignature::SEPARATORS mirrors the
// values, so a new option is one entry here and one value there.

// A line that opens, closes or underlines a markdown block: list item, ATX
// heading, quote, table row, code fence, HTML block, thematic break or setext
// underline (`---`, `===`), and an indented line that may be a code block.
const MARKDOWN_BLOCK_LINE =
  /^( {4}|\t| {0,3}([-*+] |\d{1,9}[.)] |#{1,6}( |$)|>|\||```|~~~|<[a-zA-Z/!?]|([-*_=])( *\4){2,} *$))/;

// A lone newline is a markdown soft break, which the Email and Line renderers
// turn into a space, so two plain lines are joined by a hard break. Next to a
// block neither works: a following line is swallowed by the list, quote or
// table above it (lazy continuation), `2. item` below a line joins its
// paragraph, and a hard break leaves a literal `\` or keeps a fence open. Only
// a blank line keeps a block apart, so that is what separates them there.
const lineBreakBetween = (upper, lower) => {
  const lastLine = upper.split('\n').pop();
  const firstLine = lower.split('\n')[0];
  return MARKDOWN_BLOCK_LINE.test(lastLine) ||
    MARKDOWN_BLOCK_LINE.test(firstLine)
    ? '\n\n'
    : '\\\n';
};

export const SIGNATURE_SEPARATORS = [
  {
    value: 'blank',
    labelKey:
      'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.SIGNATURE_SEPARATOR.OPTIONS.BLANK',
    delimiter: () => '\n\n',
    previewHtml: '<p></p>',
    editorLine: null,
  },
  {
    value: '--',
    labelKey:
      'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.SIGNATURE_SEPARATOR.OPTIONS.HORIZONTAL_LINE',
    delimiter: () => '\n\n--\n\n',
    previewHtml: '<p>--</p>',
    editorLine: '--',
  },
  {
    value: 'none',
    labelKey:
      'PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE_SECTION.SIGNATURE_SEPARATOR.OPTIONS.NONE',
    delimiter: lineBreakBetween,
    previewHtml: '',
    editorLine: null,
  },
];

export const DEFAULT_SIGNATURE_SEPARATOR = SIGNATURE_SEPARATORS[0].value;

export const findSignatureSeparator = value =>
  SIGNATURE_SEPARATORS.find(separator => separator.value === value) ||
  SIGNATURE_SEPARATORS[0];
