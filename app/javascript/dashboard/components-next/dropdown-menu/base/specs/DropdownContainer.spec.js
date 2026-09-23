import { h } from 'vue';
import { mount } from '@vue/test-utils';
import DropdownContainer from '../DropdownContainer.vue';

const mountDropdown = () =>
  mount(DropdownContainer, {
    slots: {
      trigger: ({ toggle }) =>
        h('button', { 'data-testid': 'trigger', onClick: toggle }, 'Open'),
      default: '<ul data-testid="menu"><li>Item</li></ul>',
    },
    global: { provide: {} },
    attachTo: document.body,
  });

const pressEscape = () => {
  const event = new KeyboardEvent('keydown', {
    key: 'Escape',
    bubbles: true,
    cancelable: true,
  });
  document.body.dispatchEvent(event);
  return event;
};

describe('DropdownContainer', () => {
  it('closes an open menu on Escape and marks the Escape as handled', async () => {
    const wrapper = mountDropdown();
    await wrapper.get('[data-testid="trigger"]').trigger('click');

    const event = pressEscape();
    await wrapper.vm.$nextTick();

    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(event.defaultPrevented).toBe(true);
    wrapper.unmount();
  });

  it('leaves an Escape alone while the menu is closed', async () => {
    const wrapper = mountDropdown();

    const event = pressEscape();
    await wrapper.vm.$nextTick();

    expect(event.defaultPrevented).toBe(false);
    expect(wrapper.emitted('close')).toBeUndefined();
    wrapper.unmount();
  });
});
