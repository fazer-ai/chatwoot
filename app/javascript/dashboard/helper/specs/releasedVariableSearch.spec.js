import { EditorState, Selection } from '@chatwoot/prosemirror-schema';
import { Schema } from 'prosemirror-model';
import { releasedVariableSearchTransaction } from '../editorHelper';

const schema = new Schema({
  nodes: {
    doc: { content: 'paragraph+' },
    paragraph: { content: 'text*', toDOM: () => ['p', 0] },
    text: {},
  },
});

// A paragraph holding `text`, with the caret at its end, where typing leaves it.
const stateWith = text => {
  const doc = schema.node('doc', null, [
    schema.node('paragraph', null, text ? [schema.text(text)] : []),
  ]);
  return EditorState.create({ schema, doc, selection: Selection.atEnd(doc) });
};

const textAfter = (state, transaction) =>
  state.apply(transaction).doc.textContent;

describe('releasedVariableSearchTransaction', () => {
  it('puts what was typed in the picker where the caret is', () => {
    const state = stateWith('Estava com: {{');
    const range = { from: 13, to: 15 };

    const transaction = releasedVariableSearchTransaction(state, range, {
      text: 'contato.apelido',
    });

    expect(textAfter(state, transaction)).toBe('Estava com: {{contato.apelido');
  });

  it('adds after a variable that came from the document, keeping its braces', () => {
    const state = stateWith('Tab: {{conversation.before.assignee.name}}');
    const range = { from: 6, to: 43 };

    const transaction = releasedVariableSearchTransaction(state, range, {
      text: ' ok',
    });

    expect(textAfter(state, transaction)).toBe(
      'Tab: {{conversation.before.assignee.name}} ok'
    );
  });

  it('replaces the document part the search was edited into, keeping the closing braces', () => {
    const state = stateWith('Oi {{contact.na}}');
    const range = { from: 4, to: 18 };

    const transaction = releasedVariableSearchTransaction(state, range, {
      text: 'contact.x',
      replace: true,
    });

    expect(textAfter(state, transaction)).toBe('Oi {{contact.x}}');
  });

  it('keeps the braces and the punctuation after the variable it replaces', () => {
    const state = stateWith('Oi {{contact.name}}, tudo bem');
    const range = { from: 4, to: 21 };

    const transaction = releasedVariableSearchTransaction(state, range, {
      text: 'contact.x',
      replace: true,
    });

    expect(textAfter(state, transaction)).toBe('Oi {{contact.x}}, tudo bem');
  });

  it('keeps the punctuation after a variable that was never closed', () => {
    const state = stateWith('Oi {{contact.na, ok');
    const range = { from: 4, to: 17 };

    const transaction = releasedVariableSearchTransaction(state, range, {
      text: 'contact.x',
      replace: true,
    });

    expect(textAfter(state, transaction)).toBe('Oi {{contact.x, ok');
  });

  it('leaves the caret before the kept braces, so typing goes on inside the variable', () => {
    const state = stateWith('Oi {{contact.na}}');
    const range = { from: 4, to: 18 };

    const replaced = state.apply(
      releasedVariableSearchTransaction(state, range, {
        text: 'contact.x',
        replace: true,
      })
    );

    expect(replaced.apply(replaced.tr.insertText('yz')).doc.textContent).toBe(
      'Oi {{contact.xyz}}'
    );
  });

  it('leaves the caret after what was handed back at the caret', () => {
    const state = stateWith('Oi {{');

    const released = state.apply(
      releasedVariableSearchTransaction(
        state,
        { from: 4, to: 6 },
        { text: 'contato' }
      )
    );

    expect(
      released.apply(released.tr.insertText('.apelido}}')).doc.textContent
    ).toBe('Oi {{contato.apelido}}');
  });

  it('does nothing when nothing was typed', () => {
    const state = stateWith('Oi {{');

    expect(
      releasedVariableSearchTransaction(state, { from: 4, to: 6 }, { text: '' })
    ).toBeNull();
  });
});
