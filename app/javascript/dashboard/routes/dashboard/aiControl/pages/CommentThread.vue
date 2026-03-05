<script setup>
import { computed } from 'vue';

const props = defineProps({
  comments: {
    type: Array,
    default: () => [],
  },
  replyingTo: {
    type: Object,
    default: null,
  },
  depth: {
    type: Number,
    default: 0,
  },
});

const emit = defineEmits(['reply']);

const MAX_DEPTH = 4;

// Build nested comment tree from flat list
const commentTree = computed(() => {
  if (!Array.isArray(props.comments)) return [];

  // If comments already have replies property, they're already processed nodes
  if (props.comments.length > 0 && props.comments[0].replies !== undefined) {
    return props.comments;
  }

  const commentMap = {};
  const rootComments = [];

  // First pass: create map of all comments by comment_id (not id!)
  props.comments.forEach(c => {
    commentMap[c.comment_id] = { ...c, replies: [] };
  });

  // Second pass: build tree structure using parent_comment_id
  props.comments.forEach(c => {
    const node = commentMap[c.comment_id];
    if (c.parent_comment_id && commentMap[c.parent_comment_id]) {
      // Parent exists, add as reply
      commentMap[c.parent_comment_id].replies.push(node);
    } else {
      // No parent or parent not in this conversation, add as root
      rootComments.push(node);
    }
  });

  return rootComments;
});

const timeAgo = (iso) => {
  if (!iso) return '';
  try {
    const diff = Date.now() - new Date(iso).getTime();
    const mins = Math.floor(diff / 60000);
    if (mins < 1) return 'vừa xong';
    if (mins < 60) return `${mins}p`;
    const hours = Math.floor(mins / 60);
    if (hours < 24) return `${hours}h`;
    const days = Math.floor(hours / 24);
    return `${days}d`;
  } catch {
    return '';
  }
};

const handleReply = (msg) => {
  emit('reply', msg);
};
</script>

<template>
  <div class="space-y-3">
    <template v-for="msg in commentTree" :key="msg.id">
      <!-- Comment Item -->
      <div
        class="group"
        :class="depth > 0 ? 'ml-4 border-l-2 border-n-slate-3 pl-3' : ''"
      >
        <div
          class="flex items-start gap-2"
          :class="msg.direction === 'outgoing' ? 'flex-row-reverse' : ''"
        >
          <!-- Avatar -->
          <div
            class="w-7 h-7 rounded-full flex-shrink-0 flex items-center justify-center text-[10px] font-bold shadow-sm"
            :class="msg.direction === 'outgoing' ? 'bg-n-teal-4 text-n-teal-11' : 'bg-n-slate-4 text-n-slate-11'"
          >
            {{ msg.direction === 'outgoing' ? '🤖' : (msg.author_name || 'U')[0].toUpperCase() }}
          </div>

          <!-- Bubble -->
          <div
            class="max-w-[80%] rounded-2xl px-3 py-2 text-sm shadow-sm relative"
            :class="
              msg.direction === 'outgoing'
                ? 'bg-n-teal-3 text-n-teal-12 rounded-tr-sm'
                : 'bg-n-slate-3 text-n-slate-12 rounded-tl-sm'
            "
          >
            <!-- Header: name + time -->
            <div class="flex items-center gap-2 mb-1">
              <span class="text-[10px] font-semibold opacity-80">
                {{ msg.direction === 'outgoing' ? 'Bot / Agent' : (msg.author_name || 'Khách') }}
              </span>
              <span class="text-[9px] opacity-50">{{ timeAgo(msg.created_at) }}</span>
            </div>
            <!-- Content -->
            <div class="text-xs leading-relaxed break-words">{{ msg.content }}</div>
          </div>
        </div>

        <!-- Reply button -->
        <div
          v-if="msg.direction === 'incoming'"
          class="mt-1 ml-9"
        >
          <button
            @click="handleReply(msg)"
            class="text-[9px] font-medium px-2 py-0.5 rounded transition-colors"
            :class="replyingTo?.id === msg.id
              ? 'bg-n-blue-3 text-n-blue-11'
              : 'text-n-slate-10 hover:text-n-blue-11 hover:bg-n-slate-2 opacity-0 group-hover:opacity-100'"
          >
            ↩️ Reply
          </button>
        </div>

        <!-- Nested Replies -->
        <div v-if="msg.replies && msg.replies.length && depth < MAX_DEPTH" class="mt-2">
          <CommentThread
            :comments="msg.replies"
            :replying-to="replyingTo"
            :depth="depth + 1"
            @reply="handleReply"
          />
        </div>
      </div>
    </template>
  </div>
</template>