<script setup>
import { computed, ref } from 'vue';
import BaseBubble from './Base.vue';
import { useMessageContext } from '../provider.js';

defineOptions({
  name: 'TraceBubble',
});

const { content, contentAttributes } = useMessageContext();
const isExpanded = ref(false);

const traceType = computed(() => {
  return (
    contentAttributes.value?.traceType ||
    contentAttributes.value?.trace_type ||
    'session_trace'
  );
});

const contextMessage = computed(() => {
  return (
    contentAttributes.value?.contextMessage ||
    contentAttributes.value?.context_message ||
    {}
  );
});

const roleLabel = computed(() => {
  return contextMessage.value?.role || 'assistant';
});

const triggerMessageId = computed(() => {
  return (
    contentAttributes.value?.source?.triggerMessageId ||
    contentAttributes.value?.source?.trigger_message_id ||
    null
  );
});

const toolCallId = computed(() => {
  return (
    contextMessage.value?.toolCallId ||
    contextMessage.value?.tool_call_id ||
    null
  );
});

const toolCallCount = computed(() => {
  const toolCalls =
    contextMessage.value?.toolCalls || contextMessage.value?.tool_calls || [];
  return Array.isArray(toolCalls) ? toolCalls.length : 0;
});

const toolCalls = computed(() => {
  const value =
    contextMessage.value?.toolCalls || contextMessage.value?.tool_calls || [];
  return Array.isArray(value) ? value : [];
});

const firstToolCall = computed(() => {
  return toolCalls.value[0] || null;
});

const traceBody = computed(() => {
  const traceContent =
    contextMessage.value?.content !== undefined
      ? contextMessage.value.content
      : content.value;

  if (typeof traceContent === 'string') {
    return traceContent.trim();
  }

  if (Array.isArray(traceContent)) {
    return traceContent
      .map(part => {
        if (typeof part === 'string') return part;
        if (typeof part?.text === 'string') return part.text;
        if (typeof part?.type === 'string') return `[${part.type}]`;
        return '';
      })
      .filter(Boolean)
      .join('\n');
  }

  if (traceContent && typeof traceContent === 'object') {
    return JSON.stringify(traceContent, null, 2);
  }

  return 'No trace content';
});

const sanitizeSystemText = value => {
  if (typeof value !== 'string') return '';

  return value
    .replace(/<system>([\s\S]*?)<\/system>/g, '$1')
    .replace(/\[CHATWOOT_CONTEXT\][\s\S]*?USER_MESSAGE:\s*/g, '')
    .replace(/\[\/CHATWOOT_CONTEXT\]/g, '')
    .trim();
};

const compactPath = value => {
  if (typeof value !== 'string') return '';

  const normalized = value.replace(/\\/g, '/');
  const preferredPrefixes = ['/chatbotlevan/', '/chatwoot-wsl/', '/kimi-cli-fork/'];
  const matchingPrefix = preferredPrefixes.find(prefix =>
    normalized.includes(prefix)
  );

  if (matchingPrefix) {
    return normalized.split(matchingPrefix).pop();
  }

  const wikiIndex = normalized.indexOf('/wiki/');
  if (wikiIndex >= 0) {
    return normalized.slice(wikiIndex + 1);
  }

  return normalized.split('/').slice(-2).join('/');
};

const truncate = (value, maxLength = 96) => {
  const normalized = String(value || '').replace(/\s+/g, ' ').trim();
  if (normalized.length <= maxLength) return normalized;
  return `${normalized.slice(0, maxLength - 1)}…`;
};

const parseMaybeJson = value => {
  if (typeof value !== 'string') return value;

  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
};

const summarizeToolCall = toolCall => {
  const toolName = toolCall?.function?.name || 'Tool';
  const rawArguments = toolCall?.function?.arguments;
  const parsedArguments = parseMaybeJson(rawArguments);

  if (parsedArguments && typeof parsedArguments === 'object') {
    if (parsedArguments.path) {
      return `Used ${toolName} (${compactPath(parsedArguments.path)})`;
    }

    if (parsedArguments.pattern) {
      return `Used ${toolName} (${parsedArguments.pattern})`;
    }

    if (parsedArguments.query_text) {
      return `Using ${toolName} (${truncate(
        JSON.stringify({
          query_text: parsedArguments.query_text,
          top_k: parsedArguments.top_k,
        }),
        88
      )})`;
    }

    return `Using ${toolName} (${truncate(
      JSON.stringify(parsedArguments),
      88
    )})`;
  }

  if (typeof parsedArguments === 'string' && parsedArguments.trim()) {
    return `Using ${toolName} (${truncate(parsedArguments, 88)})`;
  }

  return `Using ${toolName}`;
};

const summarizeTraceText = value => {
  const normalized = sanitizeSystemText(value);
  const firstMeaningfulLine = normalized
    .split('\n')
    .map(line => line.trim())
    .find(Boolean);

  if (!firstMeaningfulLine) {
    return 'Trace event';
  }

  return truncate(firstMeaningfulLine, 110);
};

const summaryText = computed(() => {
  if (firstToolCall.value) {
    return summarizeToolCall(firstToolCall.value);
  }

  if (roleLabel.value === 'user') {
    return `User: ${summarizeTraceText(traceBody.value)}`;
  }

  return summarizeTraceText(traceBody.value);
});

const summaryTone = computed(() => {
  const lowered = summaryText.value.toLowerCase();

  if (
    ['error', 'failed', 'not found', 'unsafe', 'invalid', 'missing'].some(
      token => lowered.includes(token)
    )
  ) {
    return {
      text: 'text-n-ruby-9',
      dot: 'bg-n-ruby-9',
    };
  }

  if (firstToolCall.value) {
    return {
      text: 'text-n-blue-text',
      dot: 'bg-n-blue-text',
    };
  }

  if (roleLabel.value === 'tool') {
    return {
      text: 'text-n-teal-11',
      dot: 'bg-n-teal-10',
    };
  }

  if (roleLabel.value === 'user') {
    return {
      text: 'text-n-amber-9',
      dot: 'bg-n-amber-9',
    };
  }

  return {
    text: 'text-n-slate-1',
    dot: 'bg-n-slate-8',
  };
});

const detailPayload = computed(() => {
  return JSON.stringify(contextMessage.value, null, 2);
});

const detailArguments = computed(() => {
  const rawArguments = firstToolCall.value?.function?.arguments;
  if (!rawArguments) return null;

  const parsedArguments = parseMaybeJson(rawArguments);
  if (typeof parsedArguments === 'string') {
    return parsedArguments;
  }

  return JSON.stringify(parsedArguments, null, 2);
});

const toggleExpanded = () => {
  isExpanded.value = !isExpanded.value;
};
</script>

<template>
  <BaseBubble class="w-full max-w-2xl overflow-hidden" data-bubble-name="trace">
    <button
      type="button"
      class="w-full px-3 py-2 flex items-start gap-2 font-mono text-xs text-left hover:bg-n-alpha-2 transition-colors"
      data-testid="trace-toggle"
      @click="toggleExpanded"
    >
      <span
        class="mt-1.5 size-1.5 rounded-full shrink-0"
        :class="summaryTone.dot"
      />
      <span
        class="min-w-0 flex-1 leading-5 break-words"
        :class="summaryTone.text"
        data-testid="trace-summary"
      >
        {{ summaryText }}
      </span>
      <span class="shrink-0 text-n-slate-9">
        {{ isExpanded ? 'Hide' : 'View' }}
      </span>
    </button>

    <div
      v-if="isExpanded"
      class="px-3 py-3 border-t border-n-slate-7 flex flex-col gap-3 font-mono text-xs"
      data-testid="trace-detail"
    >
      <div class="flex flex-wrap items-center gap-2 uppercase tracking-[0.2em]">
        <span class="trace-chip px-2 py-1 rounded-full">{{ roleLabel }}</span>
        <span class="trace-chip px-2 py-1 rounded-full">{{ traceType }}</span>
        <span v-if="toolCallCount" class="trace-chip px-2 py-1 rounded-full">
          {{ toolCallCount }} tool call<span v-if="toolCallCount > 1">s</span>
        </span>
        <span v-if="toolCallId" class="trace-chip px-2 py-1 rounded-full">
          {{ toolCallId }}
        </span>
        <span
          v-if="triggerMessageId"
          class="trace-chip px-2 py-1 rounded-full"
        >
          trigger #{{ triggerMessageId }}
        </span>
      </div>

      <div v-if="detailArguments" class="flex flex-col gap-1">
        <span class="uppercase tracking-[0.18em] text-n-slate-9">
          Arguments
        </span>
        <pre class="whitespace-pre-wrap break-words m-0 leading-5">{{
          detailArguments
        }}</pre>
      </div>

      <div class="flex flex-col gap-1">
        <span class="uppercase tracking-[0.18em] text-n-slate-9">
          Payload
        </span>
        <pre class="whitespace-pre-wrap break-words m-0 leading-5">{{
          detailPayload
        }}</pre>
      </div>
    </div>
  </BaseBubble>
</template>
