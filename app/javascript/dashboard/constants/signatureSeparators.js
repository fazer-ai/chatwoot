// The message signature separators. InboxSignature::SEPARATORS mirrors the
// values, so a new option is one entry here and one value there.

// Markdown blocks that a hard break cannot touch: next to a list item,
// heading, quote, table row or code fence, the `\` is left behind as text (or
// keeps a closing fence from closing).
const MARKDOWN_BLOCK_LINE =
  /^ {0,3}([-*+] |\d{1,9}[.)] |#{1,6}( |$)|>|\||```|~~~)/;

// A lone newline is a markdown soft break, which the Email and Line renderers
// turn into a space, so two plain lines are joined by a hard break instead.
const lineBreakBetween = (upper, lower) => {
  const lastLine = upper.split('\n').pop();
  const firstLine = lower.split('\n')[0];
  return MARKDOWN_BLOCK_LINE.test(lastLine) ||
    MARKDOWN_BLOCK_LINE.test(firstLine)
    ? '\n'
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
