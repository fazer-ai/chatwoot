import { mount, flushPromises } from '@vue/test-utils';
import ImageEditor from '../ImageEditor.vue';

const file = new File(['original'], 'photo.jpg', { type: 'image/jpeg' });

const fakeContext = {
  drawImage: vi.fn(),
  clearRect: vi.fn(),
  strokeRect: vi.fn(),
  save: vi.fn(),
  restore: vi.fn(),
  beginPath: vi.fn(),
  moveTo: vi.fn(),
  lineTo: vi.fn(),
  closePath: vi.fn(),
  stroke: vi.fn(),
  fill: vi.fn(),
  ellipse: vi.fn(),
  setLineDash: vi.fn(),
};

// The editor teleports to the body, so its controls are queried from the document.
const control = label => document.querySelector(`[aria-label="${label}"]`);
const button = text =>
  [...document.querySelectorAll('button')].find(
    b => b.textContent.trim() === text
  );

const click = async element => {
  element.click();
  await flushPromises();
};

// jsdom has no PointerEvent, so a MouseEvent carries the pointer fields.
const drag = async (from, to) => {
  const canvas = document.querySelector('canvas');
  [
    ['pointerdown', from],
    ['pointermove', to],
    ['pointerup', to],
  ].forEach(([type, [clientX, clientY]]) => {
    const event = new MouseEvent(type, { clientX, clientY });
    Object.assign(event, { isPrimary: true, pointerId: 1 });
    canvas.dispatchEvent(event);
  });
  await flushPromises();
};

describe('ImageEditor', () => {
  let wrapper;

  const mountEditor = async () => {
    wrapper = mount(ImageEditor, { props: { file }, attachTo: document.body });
    await flushPromises();
  };

  const savedFiles = () => (wrapper.emitted('save') || []).map(([f]) => f);

  beforeEach(() => {
    window.createImageBitmap = vi.fn(async () => ({
      width: 800,
      height: 600,
      close: vi.fn(),
    }));
    vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(
      fakeContext
    );
    HTMLCanvasElement.prototype.setPointerCapture = vi.fn();
    HTMLCanvasElement.prototype.getBoundingClientRect = () => ({
      left: 0,
      top: 0,
      width: 800,
      height: 600,
    });
    HTMLCanvasElement.prototype.toBlob = function toBlob(callback, type) {
      callback(new Blob(['edited'], { type }));
    };
  });

  afterEach(() => wrapper.unmount());

  it('sends the original file untouched when nothing was drawn', async () => {
    await mountEditor();

    await click(button('IMAGE_EDITOR.SEND'));

    expect(savedFiles()).toHaveLength(1);
    expect(savedFiles()[0]).toBe(file);
  });

  it('sends a PNG of the edited image after a drawing', async () => {
    await mountEditor();

    await drag([10, 10], [200, 150]);
    await click(button('IMAGE_EDITOR.SEND'));

    const [saved] = savedFiles();
    expect(saved).not.toBe(file);
    expect(saved.name).toBe('photo.png');
    expect(saved.type).toBe('image/png');
  });

  it('ignores a click without a drag', async () => {
    await mountEditor();

    await drag([50, 50], [51, 50]);

    expect(control('IMAGE_EDITOR.UNDO').disabled).toBe(true);
  });

  it('undo removes the drawing and redo brings it back', async () => {
    await mountEditor();
    const undo = control('IMAGE_EDITOR.UNDO');
    const redo = control('IMAGE_EDITOR.REDO');

    await drag([10, 10], [200, 150]);
    await click(undo);

    expect(undo.disabled).toBe(true);
    await click(button('IMAGE_EDITOR.SEND'));
    expect(savedFiles()[0]).toBe(file);

    await click(redo);
    expect(redo.disabled).toBe(true);
    expect(undo.disabled).toBe(false);
  });

  it('a new drawing after undo clears the redo history', async () => {
    await mountEditor();

    await drag([10, 10], [200, 150]);
    await click(control('IMAGE_EDITOR.UNDO'));
    await drag([10, 10], [200, 150]);

    expect(control('IMAGE_EDITOR.REDO').disabled).toBe(true);
  });

  it('undoes with Ctrl+Z and cancels with Escape', async () => {
    await mountEditor();

    await drag([10, 10], [200, 150]);
    document.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'z', ctrlKey: true })
    );
    await flushPromises();
    expect(control('IMAGE_EDITOR.UNDO').disabled).toBe(true);

    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    expect(wrapper.emitted('cancel')).toHaveLength(1);
  });

  it('discards the image on cancel', async () => {
    await mountEditor();

    await click(button('IMAGE_EDITOR.CANCEL'));

    expect(wrapper.emitted('cancel')).toHaveLength(1);
    expect(wrapper.emitted('save')).toBeUndefined();
  });

  it('sends the original file when the browser cannot decode it', async () => {
    window.createImageBitmap = vi.fn(async () => {
      throw new DOMException('decode failed', 'InvalidStateError');
    });

    await mountEditor();

    expect(savedFiles()[0]).toBe(file);
  });
});
