import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { defineComponent, h, nextTick, reactive, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import Whatsapp from '../Whatsapp.vue';
import WhatsappChannel from 'dashboard/api/channel/whatsappChannel';

// The picker fetches the session catalog on mount. Without this the real module reaches
// for axios and the composable's own catch swallows it, so every session provider would
// silently be missing from the picker rather than the test saying so.
vi.mock('dashboard/api/channel/whatsappChannel', () => ({
  default: { getSessionProviders: vi.fn() },
}));

const SESSION_CATALOG = [
  { key: 'uazapi', creatable: true, beta: true, fields: [] },
  { key: 'baileys', creatable: true, beta: false, legacy: true, fields: [] },
];

// Mutable reactive route — tests drive route.query / route.name through it
// to exercise how the parent reacts to navigation events.
let mockRoute;
const mockPush = vi.fn();
const mockReplace = vi.fn();
let originalChatwootConfig;

vi.mock('vue-router', async () => {
  const actual = await vi.importActual('vue-router');
  return {
    ...actual,
    useRoute: () => mockRoute,
    useRouter: () => ({ push: mockPush, replace: mockReplace }),
  };
});

// useAccount reads the Vuex store; these tests mount without one. Self-hosted
// behavior (not on cloud) keeps the embedded signup gate open, matching the
// scenarios below.
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: () => false,
    isOnChatwootCloud: ref(false),
    // Meta's incident switch, off: the picker offers the embedded signup as usual.
    isMetaInboxCreationDisabled: ref(false),
  }),
}));

vi.mock('vue-i18n', async () => {
  const actual = await vi.importActual('vue-i18n');
  return {
    ...actual,
    useI18n: () => ({ t: key => key }),
    I18nT: defineComponent({
      name: 'I18nT',
      props: { keypath: { type: String, required: true }, tag: String },
      setup(props, { slots }) {
        return () =>
          h(
            props.tag || 'span',
            {},
            slots.default ? slots.default() : props.keypath
          );
      },
    }),
  };
});

// We don't care about feature_flags / branding here — render simple stubs.
const stubComponent = name =>
  defineComponent({
    name,
    template: `<div class="${name}-stub" />`,
  });

const ChannelSelectorStub = defineComponent({
  name: 'ChannelSelector',
  // Declared so the assertion can read it back with `props()`. eslint cannot see into a
  // string template, so it reads the prop as unused.
  // eslint-disable-next-line vue/no-unused-properties
  props: { isBeta: { type: Boolean, default: false } },
  template: '<div class="ChannelSelector-stub" />',
});

const WhatsappEmbeddedSignupStub = defineComponent({
  name: 'WhatsappEmbeddedSignup',
  // eslint-disable-next-line vue/no-unused-emit-declarations
  emits: ['leaving'],
  template: '<div class="WhatsappEmbeddedSignup-stub" />',
});

const mountWhatsapp = (overrides = {}) => {
  // window.chatwootConfig is read in setup() to decide whether to render the
  // embedded signup component. Force "configured" by default so a provider
  // selection of "whatsapp" routes to the embedded signup branch.
  window.chatwootConfig = {
    whatsappAppId: 'appid',
    whatsappConfigurationId: 'configid',
  };

  return mount(Whatsapp, {
    props: {
      mode: 'convert',
      inbox: { id: 30, provider: 'baileys', name: 'Inbox 30' },
      ...overrides,
    },
    global: {
      stubs: {
        WhatsappEmbeddedSignup: WhatsappEmbeddedSignupStub,
        Twilio: stubComponent('Twilio'),
        ThreeSixtyDialogWhatsapp: stubComponent('ThreeSixtyDialogWhatsapp'),
        CloudWhatsapp: stubComponent('CloudWhatsapp'),
        ChannelSelector: ChannelSelectorStub,
        BaileysWhatsapp: stubComponent('BaileysWhatsapp'),
        ZapiWhatsapp: stubComponent('ZapiWhatsapp'),
      },
    },
  });
};

const setRouteProvider = value => {
  if (value === undefined) {
    mockRoute.query = {};
  } else {
    mockRoute.query = { provider: value };
  }
};

describe('Whatsapp.vue (convert mode)', () => {
  beforeEach(() => {
    originalChatwootConfig = window.chatwootConfig;
    mockPush.mockReset();
    mockReplace.mockReset();
    WhatsappChannel.getSessionProviders.mockResolvedValue({
      data: { payload: SESSION_CATALOG },
    });
    mockRoute = reactive({
      name: 'settings_inbox_convert',
      params: { inboxId: 30 },
      query: {},
    });
  });

  afterEach(() => {
    window.chatwootConfig = originalChatwootConfig;
  });

  it('shows the provider picker when no provider is selected in the query', () => {
    const wrapper = mountWhatsapp();
    expect(wrapper.find('.ChannelSelector-stub').exists()).toBe(true);
    expect(wrapper.find('.WhatsappEmbeddedSignup-stub').exists()).toBe(false);
  });

  it('shows the embedded signup configuration when ?provider=whatsapp', async () => {
    setRouteProvider('whatsapp');
    const wrapper = mountWhatsapp();
    await nextTick();
    expect(wrapper.find('.WhatsappEmbeddedSignup-stub').exists()).toBe(true);
    expect(wrapper.find('.ChannelSelector-stub').exists()).toBe(false);
  });

  // The badge is what tells the admin a provider is not settled yet, and it follows the
  // catalog rather than the label, so a provider leaving beta is a server-side change.
  it('badges the session providers the catalog reports as beta', async () => {
    const wrapper = mountWhatsapp();
    await flushPromises();

    const badged = wrapper
      .findAllComponents(ChannelSelectorStub)
      .filter(selector => selector.props('isBeta'));

    expect(
      wrapper.findAllComponents(ChannelSelectorStub).length
    ).toBeGreaterThan(badged.length);
    expect(badged).toHaveLength(1);
  });

  // Reproduces the "flash" bug: a successful embedded signup runs
  // router.replace, the route's query.provider is cleared during the
  // navigation tail, and the still-mounted parent would re-render the
  // provider picker for a few frames between the success toast and the
  // unmount.
  describe('navigation tail after embedded signup success', () => {
    it('keeps the picker hidden once the child emits "leaving"', async () => {
      setRouteProvider('whatsapp');
      const wrapper = mountWhatsapp();
      await nextTick();
      expect(wrapper.find('.WhatsappEmbeddedSignup-stub').exists()).toBe(true);

      // Simulate the success path: child signals it is about to navigate,
      // then the route's query.provider is cleared (as router.replace would).
      await wrapper
        .findComponent(WhatsappEmbeddedSignupStub)
        .vm.$emit('leaving');
      setRouteProvider(undefined);
      await nextTick();

      // Neither the picker nor the configuration block should render.
      expect(wrapper.find('.ChannelSelector-stub').exists()).toBe(false);
      expect(wrapper.find('.WhatsappEmbeddedSignup-stub').exists()).toBe(false);
    });

    it('would flash the picker without the "leaving" signal (control)', async () => {
      setRouteProvider('whatsapp');
      const wrapper = mountWhatsapp();
      await nextTick();
      expect(wrapper.find('.WhatsappEmbeddedSignup-stub').exists()).toBe(true);

      // Simulate the route's query being cleared without the leaving signal.
      // This is the original buggy behavior: the picker reappears.
      setRouteProvider(undefined);
      await nextTick();

      expect(wrapper.find('.ChannelSelector-stub').exists()).toBe(true);
    });
  });
});
