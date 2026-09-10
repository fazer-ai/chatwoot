import {
  clipboardCarriesText,
  splitFilesBySize,
  usableFilesFromTransfer,
} from '../pastedFiles';

// The shapes below are not invented: they were measured on 10/09/2026, macOS, Chromium 153,
// by pasting each source into a probe page and reading `e.clipboardData`. The record lives in
// the round's holdout folder (clipboard-measurements.json). Two of them decide the whole
// question, and they are the two the issue said had to be measured before shipping:
//
//   * a Numbers copy really does carry an invalid zero-byte attachment, and it is `image.png`
//     of `image/png`, never a spreadsheet file. It arrives WITH text/plain, text/html and
//     text/rtf, because the point of copying a cell is to paste its text somewhere.
//   * a file copied in Finder arrives as `Files` alone. The macOS pasteboard does carry the
//     file name as text, and the browser drops it, so `types` has no text flavour at all.
//
// That asymmetry is the whole discriminator: warn when every pasted file is empty and nothing
// on the clipboard is text, stay quiet otherwise.
const transfer = (types, files) => ({
  types,
  files: files.map(([name, type, size]) => ({ name, type, size })),
});

const NUMBERS_SINGLE_CELL = transfer(
  ['text/plain', 'text/html', 'text/rtf', 'Files'],
  [['image.png', 'image/png', 0]]
);
const NUMBERS_RANGE = NUMBERS_SINGLE_CELL;
const FINDER_ZERO_BYTE_FILE = transfer(
  ['Files'],
  [['vazio.txt', 'text/plain', 0]]
);
const FINDER_VALID_FILE = transfer(
  ['Files'],
  [['valido.txt', 'text/plain', 4]]
);
const SCREENSHOT = transfer(['Files'], [['image.png', 'image/png', 40656]]);
const PLAIN_TEXT = transfer(['text/plain'], []);

describe('pastedFiles', () => {
  describe('clipboardCarriesText', () => {
    it('is true for the shapes a rich copy produces', () => {
      expect(clipboardCarriesText(NUMBERS_SINGLE_CELL)).toBe(true);
      expect(clipboardCarriesText(PLAIN_TEXT)).toBe(true);
    });

    it('is false for a file copy, which the browser reports as Files alone', () => {
      expect(clipboardCarriesText(FINDER_ZERO_BYTE_FILE)).toBe(false);
      expect(clipboardCarriesText(SCREENSHOT)).toBe(false);
    });

    // Each flavour on its own, because a copy does not always bring all three: a web page gives
    // text/html, a rich text editor gives text/rtf, and treating any one of them as "no text"
    // would put the spurious alert back for that source alone.
    it.each(['text/plain', 'text/html', 'text/rtf'])(
      'counts %s on its own as text',
      type => {
        expect(
          clipboardCarriesText(
            transfer([type, 'Files'], [['image.png', 'image/png', 0]])
          )
        ).toBe(true);
      }
    );

    it('survives a transfer with no types at all', () => {
      expect(clipboardCarriesText(undefined)).toBe(false);
      expect(clipboardCarriesText({})).toBe(false);
    });
  });

  describe('splitFilesBySize', () => {
    it('keeps the order and drops nothing on the floor', () => {
      const files = [
        { name: 'a.png', size: 0 },
        { name: 'b.png', size: 10 },
        { name: 'c.png', size: 0 },
      ];

      expect(splitFilesBySize(files)).toEqual({
        files: [{ name: 'b.png', size: 10 }],
        empty: [
          { name: 'a.png', size: 0 },
          { name: 'c.png', size: 0 },
        ],
      });
    });

    it('ignores holes rather than crashing on them', () => {
      expect(splitFilesBySize([null, undefined])).toEqual({
        files: [],
        empty: [],
      });
      expect(splitFilesBySize(null)).toEqual({ files: [], empty: [] });
    });
  });

  describe('usableFilesFromTransfer', () => {
    it('stays quiet for a Numbers paste, which is why the filter exists', () => {
      expect(usableFilesFromTransfer(NUMBERS_SINGLE_CELL)).toEqual({
        files: [],
        shouldAlertEmpty: false,
      });
      expect(usableFilesFromTransfer(NUMBERS_RANGE).shouldAlertEmpty).toBe(
        false
      );
    });

    it('explains the refusal for a genuine empty file', () => {
      expect(usableFilesFromTransfer(FINDER_ZERO_BYTE_FILE)).toEqual({
        files: [],
        shouldAlertEmpty: true,
      });
    });

    it('says nothing when there was nothing to drop', () => {
      expect(usableFilesFromTransfer(FINDER_VALID_FILE)).toEqual({
        files: [{ name: 'valido.txt', type: 'text/plain', size: 4 }],
        shouldAlertEmpty: false,
      });
      expect(usableFilesFromTransfer(SCREENSHOT).shouldAlertEmpty).toBe(false);
      expect(usableFilesFromTransfer(PLAIN_TEXT).shouldAlertEmpty).toBe(false);
    });

    it('keeps the valid file and still explains the empty one beside it', () => {
      const mixed = transfer(
        ['Files'],
        [
          ['vazio.txt', 'text/plain', 0],
          ['valido.txt', 'text/plain', 4],
        ]
      );

      expect(usableFilesFromTransfer(mixed)).toEqual({
        files: [{ name: 'valido.txt', type: 'text/plain', size: 4 }],
        shouldAlertEmpty: true,
      });
    });
  });
});
