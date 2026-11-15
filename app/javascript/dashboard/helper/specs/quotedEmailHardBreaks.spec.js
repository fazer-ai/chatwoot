import {
  appendQuotedTextToMessage,
  formatQuotedTextAsBlockquote,
} from '../quotedEmailHelper';

// A markdown hard break written as two or more trailing spaces (the "No blank
// line" signature separator, pasted markdown, API-created messages) has to
// survive the quoted history, or its two lines render as one paragraph in the
// email (#977).
describe('quoted history keeps hard breaks', () => {
  it('keeps a two-space hard break on the quoted line', () => {
    expect(formatQuotedTextAsBlockquote('Equipe Acme  \nOlá')).toBe(
      '> Equipe Acme  \n> Olá'
    );
  });

  it('keeps a longer run of trailing spaces as a hard break', () => {
    expect(formatQuotedTextAsBlockquote('Linha A    \nLinha B')).toBe(
      '> Linha A  \n> Linha B'
    );
  });

  it('keeps the hard break of a nested quote line', () => {
    expect(formatQuotedTextAsBlockquote('> Antiga  \n> Resposta')).toBe(
      '> > Antiga  \n> > Resposta'
    );
  });

  it('drops a single trailing space, which is not a hard break', () => {
    expect(formatQuotedTextAsBlockquote('Linha P \nLinha Q')).toBe(
      '> Linha P\n> Linha Q'
    );
  });

  it('drops trailing tabs, which are not a hard break', () => {
    expect(formatQuotedTextAsBlockquote('Linha P\t\t\nLinha Q')).toBe(
      '> Linha P\n> Linha Q'
    );
  });

  it('leaves a backslash hard break as it is', () => {
    expect(formatQuotedTextAsBlockquote('Linha X\\\nLinha Y')).toBe(
      '> Linha X\\\n> Linha Y'
    );
  });

  it('turns a whitespace-only line into an empty quote line', () => {
    expect(formatQuotedTextAsBlockquote('Linha 1\n   \nLinha 3')).toBe(
      '> Linha 1\n>\n> Linha 3'
    );
  });

  it('keeps the hard break when the quote is appended to a reply', () => {
    expect(
      appendQuotedTextToMessage('Nova resposta', 'Equipe Acme  \nOlá', 'Header')
    ).toBe('Nova resposta\n\n> Header\n>\n> Equipe Acme  \n> Olá');
  });
});
