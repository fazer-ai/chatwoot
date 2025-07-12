import {
  messageSchema,
  MessageMarkdownTransformer,
  MessageMarkdownSerializer,
} from '@chatwoot/prosemirror-schema';
import { replaceVariablesInMessage } from '@chatwoot/utils';
import * as Sentry from '@sentry/vue';

/**
 * The delimiter used to separate the signature from the rest of the body.
 * @type {string}
 */
export const SIGNATURE_DELIMITER = '--';

/**
 * Parse and Serialize the markdown text to remove any extra spaces or new lines
 */
export function cleanSignature(signature) {
  try {
    // remove any horizontal rule tokens
    signature = signature
      .replace(/^( *\* *){3,} *$/gm, '')
      .replace(/^( *- *){3,} *$/gm, '')
      .replace(/^( *_ *){3,} *$/gm, '');

    const nodes = new MessageMarkdownTransformer(messageSchema).parse(
      signature
    );
    return MessageMarkdownSerializer.serialize(nodes);
  } catch (e) {
    // eslint-disable-next-line no-console
    console.warn(e);
    Sentry.captureException(e);
    // The parser can break on some cases
    // for example, Token type `hr` not supported by Markdown parser
    return signature;
  }
}

/**
 * Check if there's an unedited signature at the the body
 * If there is, return the index of the signature, If there isn't, return -1
 *
 * @param {string} body - The body to search for the signature.
 * @param {string} signature - The signature to search for.
 * @returns { { index: number, position: string } } - An object containing the index of the signature and its position ('start' or 'end').
 * If the signature is not found, returns -1.
 */
export function findSignatureInBody(body, signature) {
  const trimmedBody = body.trimEnd();
  const cleanedSignature = cleanSignature(signature);
  // check if body ends with signature
  if (trimmedBody.endsWith(cleanedSignature)) {
    return { index: body.lastIndexOf(cleanedSignature), position: 'bottom' };
  }
  if (trimmedBody.startsWith(cleanedSignature)) {
    return { index: cleanedSignature.length, position: 'top' };
  }

  return -1;
}

/**
 * Appends the signature to the body, separated by the signature delimiter.
 *
 * @param {string} body - The body to append the signature to.
 * @param {string} signature - The signature to append.
 * @param {Object} settings - The signature settings (position, separator).
 * @returns {string} - The body with the signature appended.
 */
export function appendSignature(body, signature, settings = {}) {
  const position = settings.position || 'top';
  const separator = settings.separator || 'blank';
  const cleanedSignature = cleanSignature(signature);
  // if signature is already present, return body
  if (findSignatureInBody(body, cleanedSignature) > -1) {
    return body;
  }

  let delimiter = '';
  if (separator === 'blank') {
    delimiter = '';
  } else if (separator === '--') {
    delimiter = '\\--';
  } else {
    delimiter = separator;
  }
  if (position === 'top') {
    return `${cleanedSignature}\n${delimiter}\n${body.trimStart()}`;
  }
  return `${body.trimEnd()}\n${delimiter}\n${cleanedSignature}`;
}

/**
 * Removes the signature from the body, along with the signature delimiter.
 *
 * @param {string} body - The body to remove the signature from.
 * @param {string} signature - The signature to remove.
 * @param {Object} settings - The signature settings (position, separator).
 * @returns {string} - The body with the signature removed.
 */
export function removeSignature(body, signature, separator = 'blank') {
  const cleanedSignature = cleanSignature(signature);
  const signatureFound = findSignatureInBody(body, cleanedSignature);

  // NOTE: Signature not found, return original body
  if (signatureFound === -1) {
    return body;
  }

  let newBody = body;
  const actualSeparator = separator === '--' ? '\\--' : separator;
  const delimiterLength =
    separator === 'blank' ? 0 : actualSeparator.length + 2;
  if (signatureFound.position === 'top') {
    // NOTE: Remove delimiter after signature: `<cleanedSignature>\n<separator>\n<messageContent>`
    const signatureEndIndex = signatureFound.index + delimiterLength;
    newBody = newBody.substring(signatureEndIndex).trimStart();
  } else if (signatureFound.position === 'bottom') {
    // NOTE: Remove delimiter before signature: `<messageContent>\n<separator>\n<cleanedSignature>`
    const signatureStartIndex = signatureFound.index - delimiterLength;
    newBody = newBody.substring(0, signatureStartIndex).trimEnd();
  }

  return newBody;
}

/**
 * Replaces the old signature with the new signature.
 * If the old signature is not present, it will append the new signature.
 *
 * @param {string} body - The body to replace the signature in.
 * @param {string} oldSignature - The signature to replace.
 * @param {string} newSignature - The signature to replace the old signature with.
 * @param {Object} settings - The signature settings (position, separator).
 * @returns {string} - The body with the old signature replaced with the new signature.
 *
 */
export function replaceSignature(
  body,
  oldSignature,
  newSignature,
  settings = {}
) {
  const withoutSignature = removeSignature(
    body,
    oldSignature,
    settings.separator || 'blank'
  );
  return appendSignature(withoutSignature, newSignature, settings);
}

/**
 * Extract text from markdown, and remove all images, code blocks, links, headers, bold, italic, lists etc.
 * Links will be converted to text, and not removed.
 *
 * @param {string} markdown - markdown text to be extracted
 * @returns
 */
export function extractTextFromMarkdown(markdown) {
  return markdown
    .replace(/```[\s\S]*?```/g, '') // Remove code blocks
    .replace(/`.*?`/g, '') // Remove inline code
    .replace(/!\[.*?\]\(.*?\)/g, '') // Remove images before removing links
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1') // Remove links but keep the text
    .replace(/#+\s*|[*_-]{1,3}/g, '') // Remove headers, bold, italic, lists etc.
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean)
    .join('\n') // Trim each line & remove any lines only having spaces
    .replace(/\n{2,}/g, '\n') // Remove multiple consecutive newlines (blank lines)
    .trim(); // Trim any extra space
}

/**
 * Scrolls the editor view into current cursor position
 *
 * @param {EditorView} view - The Prosemirror EditorView
 *
 */
export const scrollCursorIntoView = view => {
  // Get the current selection's head position (where the cursor is).
  const pos = view.state.selection.head;

  // Get the corresponding DOM node for that position.
  const domAtPos = view.domAtPos(pos);
  const node = domAtPos.node;

  // Scroll the node into view.
  if (node && node.scrollIntoView) {
    node.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }
};

/**
 * Returns a transaction that inserts a node into editor at the given position
 * Has an optional param 'content' to check if the
 *
 * @param {Node} node - The prosemirror node that needs to be inserted into the editor
 * @param {number} from - Position in the editor where the node needs to be inserted
 * @param {number} to - Position in the editor where the node needs to be replaced
 *
 */
export function insertAtCursor(editorView, node, from, to) {
  if (!editorView) {
    return undefined;
  }

  // This is a workaround to prevent inserting content into new line rather than on the exiting line
  // If the node is of type 'doc' and has only one child which is a paragraph,
  // then extract its inline content to be inserted as inline.
  const isWrappedInParagraph =
    node.type.name === 'doc' &&
    node.childCount === 1 &&
    node.firstChild.type.name === 'paragraph';

  if (isWrappedInParagraph) {
    node = node.firstChild.content;
  }

  let tr;
  if (to) {
    tr = editorView.state.tr.replaceWith(from, to, node).insertText(` `);
  } else {
    tr = editorView.state.tr.insert(from, node);
  }
  const state = editorView.state.apply(tr);
  editorView.updateState(state);
  editorView.focus();

  return state;
}

/**
 * Determines the appropriate node and position to insert an image in the editor.
 *
 * Based on the current editor state and the provided image URL, this function finds out the correct node (either
 * a standalone image node or an image wrapped in a paragraph) and its respective position in the editor.
 *
 * 1. If the current node is a paragraph and doesn't contain an image or text, the image is inserted directly into it.
 * 2. If the current node isn't a paragraph or it's a paragraph containing text, the image will be wrapped
 *    in a new paragraph and then inserted.
 * 3. If the current node is a paragraph containing an image, the new image will be inserted directly into it.
 *
 * @param {Object} editorState - The current state of the editor. It provides necessary details like selection, schema, etc.
 * @param {string} fileUrl - The URL of the image to be inserted into the editor.
 * @returns {Object|null} An object containing details about the node to be inserted and its position. It returns null if no image node can be created.
 * @property {Node} node - The ProseMirror node to be inserted (either an image node or a paragraph containing the image).
 * @property {number} pos - The position where the new node should be inserted in the editor.
 */

export const findNodeToInsertImage = (editorState, fileUrl) => {
  const { selection, schema } = editorState;
  const { nodes } = schema;
  const currentNode = selection.$from.node();
  const {
    type: { name: typeName },
    content: { size, content },
  } = currentNode;

  const imageNode = nodes.image.create({ src: fileUrl });

  if (!imageNode) return null;

  const isInParagraph = typeName === 'paragraph';
  const needsNewLine =
    !content.some(n => n.type.name === 'image') && size !== 0 ? 1 : 0;

  return {
    node: isInParagraph ? imageNode : nodes.paragraph.create({}, imageNode),
    pos: selection.from + needsNewLine,
  };
};

/**
 * Set URL with query and size.
 *
 * @param {Object} selectedImageNode - The current selected node.
 * @param {Object} size - The size to set.
 * @param {Object} editorView - The editor view.
 */
export function setURLWithQueryAndSize(selectedImageNode, size, editorView) {
  if (selectedImageNode) {
    // Create and apply the transaction
    const tr = editorView.state.tr.setNodeMarkup(
      editorView.state.selection.from,
      null,
      {
        src: selectedImageNode.src,
        height: size.height,
      }
    );

    if (tr.docChanged) {
      editorView.dispatch(tr);
    }
  }
}

/**
 * Content Node Creation Helper Functions for
 * - mention
 * - canned response
 * - variable
 * - emoji
 */

/**
 * Centralized node creation function that handles the creation of different types of nodes based on the specified type.
 * @param {Object} editorView - The editor view instance.
 * @param {string} nodeType - The type of node to create ('mention', 'cannedResponse', 'variable', 'emoji').
 * @param {Object|string} content - The content needed to create the node, which varies based on node type.
 * @returns {Object|null} - The created ProseMirror node or null if the type is not supported.
 */
const createNode = (editorView, nodeType, content) => {
  const { state } = editorView;
  switch (nodeType) {
    case 'mention':
      return state.schema.nodes.mention.create({
        userId: content.id,
        userFullName: content.name,
      });
    case 'cannedResponse':
      return new MessageMarkdownTransformer(messageSchema).parse(content);
    case 'variable':
      return state.schema.text(`{{${content}}}`);
    case 'emoji':
      return state.schema.text(content);
    default:
      return null;
  }
};

/**
 * Object mapping types to their respective node creation functions.
 */
const nodeCreators = {
  mention: (editorView, content, from, to) => ({
    node: createNode(editorView, 'mention', content),
    from,
    to,
  }),
  cannedResponse: (editorView, content, from, to, variables) => {
    const updatedMessage = replaceVariablesInMessage({
      message: content,
      variables,
    });
    const node = createNode(editorView, 'cannedResponse', updatedMessage);
    return {
      node,
      from: node.textContent === updatedMessage ? from : from - 1,
      to,
    };
  },
  variable: (editorView, content, from, to) => ({
    node: createNode(editorView, 'variable', content),
    from,
    to,
  }),
  emoji: (editorView, content, from, to) => ({
    node: createNode(editorView, 'emoji', content),
    from,
    to,
  }),
};

/**
 * Retrieves a content node based on the specified type and content, using a functional approach to select the appropriate node creation function.
 * @param {Object} editorView - The editor view instance.
 * @param {string} type - The type of content node to create ('mention', 'cannedResponse', 'variable', 'emoji').
 * @param {string|Object} content - The content to be transformed into a node.
 * @param {Object} range - An object containing 'from' and 'to' properties indicating the range in the document where the node should be placed.
 * @param {Object} variables - Optional. Variables to replace in the content, used for 'cannedResponse' type.
 * @returns {Object} - An object containing the created node and the updated 'from' and 'to' positions.
 */
export const getContentNode = (
  editorView,
  type,
  content,
  { from, to },
  variables
) => {
  const creator = nodeCreators[type];
  return creator
    ? creator(editorView, content, from, to, variables)
    : { node: null, from, to };
};
