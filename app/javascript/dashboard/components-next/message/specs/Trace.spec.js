import { defineComponent, ref } from 'vue';
import { mount } from '@vue/test-utils';
import TraceBubble from '../bubbles/Trace.vue';
import { provideMessageContext } from '../provider';

const mountTrace = ({ content = '', contentAttributes = {} } = {}) => {
  const Harness = defineComponent({
    components: {
      TraceBubble,
    },
    setup() {
      provideMessageContext({
        content: ref(content),
        contentAttributes: ref(contentAttributes),
      });

      return {};
    },
    template: '<TraceBubble />',
  });

  return mount(Harness, {
    global: {
      stubs: {
        BaseBubble: {
          template: '<div data-bubble-name="trace"><slot /></div>',
        },
      },
    },
  });
};

describe('TraceBubble', () => {
  it('renders a compact tool summary and expands details on click', async () => {
    const wrapper = mountTrace({
      contentAttributes: {
        traceType: 'kimi_context_message',
        contextMessage: {
          role: 'assistant',
          content: [],
          toolCalls: [
            {
              type: 'function',
              id: 'tool-read-1',
              function: {
                name: 'ReadFile',
                arguments:
                  '{"path":"/home/hiep/Desktop/chatbot/chatbotlevan/wiki/index.md"}',
              },
            },
          ],
        },
        source: {
          triggerMessageId: '999',
        },
      },
    });

    expect(wrapper.text()).toContain('Session Trace');
    expect(wrapper.get('[data-testid="trace-summary"]').text()).toContain(
      'Used ReadFile (wiki/index.md)'
    );
    expect(wrapper.find('[data-testid="trace-detail"]').exists()).toBe(false);

    await wrapper.get('[data-testid="trace-toggle"]').trigger('click');

    expect(wrapper.get('[data-testid="trace-detail"]').text()).toContain(
      'tool-read-1'
    );
    expect(wrapper.get('[data-testid="trace-detail"]').text()).toContain(
      '/home/hiep/Desktop/chatbot/chatbotlevan/wiki/index.md'
    );
  });

  it('summarizes tool result errors without expanding by default', () => {
    const wrapper = mountTrace({
      content:
        '<system>File not found</system>\n/home/hiep/Desktop/chatbot/chatbotlevan/wiki/missing.md',
      contentAttributes: {
        traceType: 'kimi_context_message',
        contextMessage: {
          role: 'tool',
          content:
            '<system>File not found</system>\n/home/hiep/Desktop/chatbot/chatbotlevan/wiki/missing.md',
          toolCallId: 'tool-read-2',
        },
      },
    });

    expect(wrapper.get('[data-testid="trace-summary"]').text()).toContain(
      'File not found'
    );
    expect(wrapper.find('[data-testid="trace-detail"]').exists()).toBe(false);
  });

  it('summarizes context metrics rows for staff', () => {
    const wrapper = mountTrace({
      contentAttributes: {
        traceType: 'kimi_context_metrics',
        metrics: {
          phase: 'step_total',
          tokenCount: 213421,
          maxContextSize: 262144,
          reservedContextSize: 50000,
          contextUsage: 0.814,
        },
      },
    });

    expect(wrapper.get('[data-testid="trace-summary"]').text()).toContain(
      'Context 81.4% · 213421/262144 · reserve 50000'
    );
  });

  it('summarizes compaction lifecycle rows for staff', async () => {
    const wrapper = mountTrace({
      contentAttributes: {
        traceType: 'kimi_compaction_event',
        compaction: {
          phase: 'end',
          reason: 'context_limit_reached',
          messageCountBefore: 37,
          messageCountAfter: 3,
        },
      },
    });

    expect(wrapper.get('[data-testid="trace-summary"]').text()).toContain(
      'Compaction completed · 37 -> 3 messages'
    );

    await wrapper.get('[data-testid="trace-toggle"]').trigger('click');

    expect(wrapper.get('[data-testid="trace-detail"]').text()).toContain(
      'context_limit_reached'
    );
  });
});
