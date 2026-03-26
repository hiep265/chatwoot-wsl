import { mount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import CustomAttributes from '../CustomAttributes.vue';

const mockState = {
  selectedChat: {
    id: 235,
    custom_attributes: {},
    meta: {
      sender: {
        id: 99,
      },
    },
  },
  attributesGetter: undefined,
  contactGetter: undefined,
  uiSettings: {},
  routeParams: {},
};

const mockDispatch = vi.fn();
const mockUpdateUISettings = vi.fn();
const mockUseAlert = vi.fn();

vi.mock('vue-router', () => ({
  useRoute: () => ({
    params: mockState.routeParams,
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    dispatch: mockDispatch,
  }),
  useStoreGetters: () => ({
    getSelectedChat: {
      value: mockState.selectedChat,
    },
    'attributes/getAttributesByModel': {
      value: mockState.attributesGetter,
    },
    'contacts/getContact': {
      value: mockState.contactGetter,
    },
  }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => mockUseAlert(...args),
}));

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: {
      value: mockState.uiSettings,
    },
    updateUISettings: mockUpdateUISettings,
  }),
}));

const createWrapper = (props = {}) =>
  mount(CustomAttributes, {
    props: {
      attributeFrom: 'conversation_contact_panel',
      emptyStateMessage: 'No attributes yet',
      ...props,
    },
    global: {
      stubs: {
        Draggable: {
          props: ['list'],
          template: `
            <div data-test-id="draggable">
              <template v-for="element in list" :key="element.key">
                <slot name="item" :element="element" />
              </template>
            </div>
          `,
        },
        CustomAttribute: {
          props: ['label', 'value'],
          template:
            '<div data-test-id="custom-attribute">{{ label }}::{{ value }}</div>',
        },
        NextButton: {
          props: ['label'],
          template: '<button>{{ label }}</button>',
        },
      },
    },
  });

describe('CustomAttributes', () => {
  let consoleLogSpy;
  let consoleWarnSpy;

  beforeEach(() => {
    mockDispatch.mockReset();
    mockUpdateUISettings.mockReset();
    mockUseAlert.mockReset();

    mockState.selectedChat = {
      id: 235,
      custom_attributes: {},
      meta: {
        sender: {
          id: 99,
        },
      },
    };
    mockState.attributesGetter = undefined;
    mockState.contactGetter = undefined;
    mockState.uiSettings = {};
    mockState.routeParams = {};

    consoleLogSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    consoleWarnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
  });

  afterEach(() => {
    consoleLogSpy.mockRestore();
    consoleWarnSpy.mockRestore();
  });

  it('renders the full flow when custom attribute definitions are available', () => {
    mockState.attributesGetter = vi.fn(attributeType => {
      if (attributeType !== 'contact_attribute') return [];

      return [
        {
          id: 1,
          attribute_key: 'nickname',
          attribute_display_name: 'Nickname',
          attribute_display_type: 'text',
          attribute_values: [],
        },
      ];
    });
    mockState.contactGetter = vi.fn(() => ({
      custom_attributes: {
        nickname: 'Lan',
      },
    }));

    const wrapper = createWrapper({
      attributeType: 'contact_attribute',
      contactId: 99,
    });

    expect(mockState.attributesGetter).toHaveBeenCalledWith(
      'contact_attribute'
    );
    expect(wrapper.findAll('[data-test-id="custom-attribute"]')).toHaveLength(
      1
    );
    expect(wrapper.text()).toContain('Nickname::Lan');
    expect(mockUpdateUISettings).toHaveBeenCalledWith({
      conversation_elements_order_conversation_contact_panel: ['nickname'],
    });
    expect(consoleLogSpy).toHaveBeenNthCalledWith(
      1,
      '[ThuocTinhTuyChinh] Bat dau luong'
    );
    expect(consoleLogSpy).toHaveBeenNthCalledWith(
      2,
      '[ThuocTinhTuyChinh] Buoc 1: Da khoi tao thu tu va trang thai hien thi'
    );
    expect(consoleLogSpy).toHaveBeenNthCalledWith(
      3,
      '[ThuocTinhTuyChinh] Ket thuc luong'
    );
  });

  it('uses the warning branch and empty state when the attributes getter is missing', () => {
    mockState.contactGetter = vi.fn(() => ({
      custom_attributes: {},
    }));

    const wrapper = createWrapper({
      attributeType: 'contact_attribute',
      contactId: 99,
    });

    expect(wrapper.text()).toContain('No attributes yet');
    expect(wrapper.findAll('[data-test-id="custom-attribute"]')).toHaveLength(
      0
    );
    expect(consoleWarnSpy).toHaveBeenCalledWith(
      '[ThuocTinhTuyChinh] Canh bao tai buoc 1: Thieu getter attributes/getAttributesByModel'
    );
    expect(mockUpdateUISettings).toHaveBeenCalledWith({
      conversation_elements_order_conversation_contact_panel: [],
    });
  });

  it('stops the contact lookup flow safely when the contact record is not available', () => {
    mockState.attributesGetter = vi.fn(() => [
      {
        id: 1,
        attribute_key: 'nickname',
        attribute_display_name: 'Nickname',
        attribute_display_type: 'text',
        attribute_values: [],
      },
    ]);
    mockState.contactGetter = vi.fn(() => null);

    const wrapper = createWrapper({
      attributeType: 'contact_attribute',
      contactId: 99,
    });

    expect(wrapper.findAll('[data-test-id="custom-attribute"]')).toHaveLength(
      1
    );
    expect(wrapper.text()).toContain('Nickname::');
    expect(consoleWarnSpy).not.toHaveBeenCalled();
  });
});
