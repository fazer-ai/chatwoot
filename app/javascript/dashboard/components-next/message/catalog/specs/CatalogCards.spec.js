import { defineComponent, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import RichMessage from '../../bubbles/RichMessage.vue';
import QuotedProduct from '../QuotedProduct.vue';
import { provideMessageContext } from '../../provider.js';
import ptBR from 'dashboard/i18n/fazer-ai/locale/pt_BR/conversation.json';
import en from 'dashboard/i18n/fazer-ai/locale/en/conversation.json';

// Payloads as content_attributes reach the bubble: deep-camelized, so price_1000 is
// price1000. The values are the live order and product of fazer-ai/chatwoot#996.
const THUMB = 'data:image/jpeg;base64,/9j/4AAQ';
const product = (overrides = {}) => ({
  id: '1000000000000001',
  title: 'Caneca',
  description: 'Caneca de cerâmica, 300 ml',
  price1000: 34900,
  currency: 'BRL',
  thumbnail: THUMB,
  ...overrides,
});
const order = (overrides = {}) => ({
  id: '2000000000000001',
  title: 'Loja Exemplo',
  itemCount: 3,
  total1000: 129700,
  currency: 'BRL',
  thumbnail: THUMB,
  items: [
    {
      productId: '1000000000000002',
      name: 'Camiseta básica',
      quantity: 1,
      price1000: 59900,
      currency: 'BRL',
      image: 'https://example.invalid/catalog/camiseta.jpg',
    },
    {
      productId: '1000000000000001',
      name: 'Caneca',
      quantity: 2,
      price1000: 34900,
      currency: 'BRL',
      image: 'https://example.invalid/catalog/caneca.jpg',
    },
  ],
  ...overrides,
});

const mountWith = (
  component,
  contentAttributes,
  { locale = 'pt_BR', attachments = [] } = {}
) => {
  const Host = defineComponent({
    components: { Component: component },
    setup() {
      provideMessageContext({
        id: ref(1),
        content: ref(''),
        attachments: ref(attachments),
        contentAttributes: ref(contentAttributes),
      });
    },
    template: '<Component />',
  });
  const i18n = createI18n({
    legacy: false,
    locale,
    messages: { pt_BR: ptBR, en },
  });
  return mount(Host, {
    global: {
      plugins: [i18n],
      stubs: {
        BaseBubble: { template: '<div><slot /></div>' },
        Icon: { props: ['icon'], template: '<i :data-icon="icon" />' },
      },
    },
  });
};

// Intl puts a no-break space between the symbol and the number.
const text = wrapper => wrapper.text().replace(/\u00a0/g, ' ');

describe('catalog product card', () => {
  it('shows the photo, name, price in the agent language and the description', () => {
    const wrapper = mountWith(RichMessage, {
      rich: { type: 'product', title: 'Caneca', product: product() },
    });

    expect(wrapper.find('img').attributes('src')).toBe(THUMB);
    expect(text(wrapper)).toContain('Caneca');
    expect(text(wrapper)).toContain('R$ 34,90');
    expect(text(wrapper)).toContain('Caneca de cerâmica, 300 ml');
    expect(text(wrapper)).toContain('Produto do catálogo');
  });

  it('formats the price for an English agent', () => {
    const wrapper = mountWith(
      RichMessage,
      { rich: { type: 'product', product: product() } },
      { locale: 'en' }
    );

    expect(text(wrapper)).toContain('R$34.90');
  });

  it('strikes the original price through when there is a sale price', () => {
    const wrapper = mountWith(RichMessage, {
      rich: {
        type: 'product',
        product: product({ price1000: 59900, salePrice1000: 49900 }),
      },
    });

    expect(
      wrapper
        .find('s')
        .text()
        .replace(/\u00a0/g, ' ')
    ).toBe('R$ 59,90');
    expect(text(wrapper)).toContain('R$ 49,90');
  });

  it('never shows a missing price as zero', () => {
    const wrapper = mountWith(RichMessage, {
      rich: {
        type: 'product',
        product: product({ price1000: undefined, currency: undefined }),
      },
    });

    expect(text(wrapper)).toContain('Caneca');
    expect(text(wrapper)).not.toContain('0,00');
  });

  it('says there is a product to see on WhatsApp when nothing about it is readable', () => {
    const wrapper = mountWith(RichMessage, {
      rich: { type: 'product', product: {} },
    });

    expect(text(wrapper)).toContain(
      'Mensagem com um produto do catálogo. Veja no WhatsApp.'
    );
  });

  it('draws the delivered photo inside the card instead of a separate attachment', () => {
    const wrapper = mountWith(
      RichMessage,
      { rich: { type: 'product', product: product() } },
      {
        attachments: [
          { id: 9, fileType: 'image', dataUrl: 'https://cw/rails/photo.jpg' },
        ],
      }
    );

    expect(wrapper.findAll('img').map(img => img.attributes('src'))).toEqual([
      'https://cw/rails/photo.jpg',
    ]);
    expect(text(wrapper)).toContain('R$ 34,90');
  });
});

describe('catalog order card', () => {
  it('shows what WhatsApp shows on the card, without the seller name', () => {
    const wrapper = mountWith(RichMessage, {
      rich: {
        type: 'order',
        title: '3 items',
        footer: 'R$129.70 (estimated total)',
        order: order(),
      },
    });

    expect(wrapper.find('img').attributes('src')).toBe(THUMB);
    expect(text(wrapper)).toContain('3 itens');
    expect(text(wrapper)).toContain('R$ 129,70 (total estimado)');
    expect(text(wrapper)).toContain('Ver pedido');
    expect(text(wrapper)).not.toContain('3 items');
    expect(text(wrapper)).not.toContain('estimated total');
    expect(text(wrapper)).not.toContain('Loja Exemplo');
    expect(wrapper.findAll('[data-catalog-item]')).toHaveLength(0);
  });

  it('lists the items with name, quantity, price and picture on View order', async () => {
    const wrapper = mountWith(RichMessage, {
      rich: { type: 'order', order: order() },
    });

    await wrapper.find('button').trigger('click');

    const items = wrapper
      .findAll('[data-catalog-item]')
      .map(item => item.text().replace(/\s+/g, ' '));
    expect(items).toEqual([
      expect.stringContaining('Camiseta básica'),
      expect.stringContaining('Caneca'),
    ]);
    expect(items[0]).toContain('Quantidade: 1 · R$ 59,90');
    expect(items[1]).toContain('Quantidade: 2 · R$ 34,90');
    expect(
      wrapper.find('[data-catalog-item] img').attributes('referrerpolicy')
    ).toBe('no-referrer');
  });

  it('shows the count and total alone when the items could not be fetched', () => {
    const wrapper = mountWith(RichMessage, {
      rich: { type: 'order', order: order({ items: undefined }) },
    });

    expect(text(wrapper)).toContain('3 itens');
    expect(text(wrapper)).toContain('R$ 129,70');
    expect(wrapper.find('button').exists()).toBe(false);
  });

  it('writes one item in the singular and leaves out a missing total', () => {
    const wrapper = mountWith(RichMessage, {
      rich: {
        type: 'order',
        order: order({ itemCount: 1, total1000: undefined, items: [] }),
      },
    });

    expect(text(wrapper)).toContain('1 item');
    expect(text(wrapper)).not.toContain('1 itens');
    expect(text(wrapper)).not.toContain('total estimado');
  });
});

describe('quoted catalog product', () => {
  it('shows the product the question was asked from', () => {
    const wrapper = mountWith(QuotedProduct, { quotedProduct: product() });

    expect(text(wrapper)).toContain('Caneca');
    expect(text(wrapper)).toContain('R$ 34,90');
    expect(text(wrapper)).toContain('Produto do catálogo');
    expect(wrapper.find('img').attributes('src')).toBe(THUMB);
  });

  it('says there is a product when the quote is unreadable', () => {
    const wrapper = mountWith(QuotedProduct, { quotedProduct: {} });

    expect(text(wrapper)).toContain('Veja no WhatsApp');
    expect(text(wrapper)).not.toContain('0,00');
  });

  it('renders nothing for a message that quotes no product', () => {
    const wrapper = mountWith(QuotedProduct, {});

    expect(wrapper.find('[data-quoted-product]').exists()).toBe(false);
  });

  it('refuses a thumbnail that is not an inline image', () => {
    const wrapper = mountWith(QuotedProduct, {
      quotedProduct: product({ thumbnail: 'https://example.com/tracker.jpg' }),
    });

    expect(wrapper.find('img').exists()).toBe(false);
  });
});
