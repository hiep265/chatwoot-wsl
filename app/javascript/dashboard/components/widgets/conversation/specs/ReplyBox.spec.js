import ReplyBox from '../ReplyBox.vue';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';

describe('ReplyBox AI note payload', () => {
  it('marks AI notes as private staff instructions for the webhook', () => {
    expect(REPLY_EDITOR_MODES.AI_NOTE).toBe('AI_NOTE');

    const payload = ReplyBox.methods.getMessagePayload.call(
      {
        attachedFiles: [],
        bccEmails: '',
        ccEmails: '',
        currentChat: { id: 123 },
        getMessageWithQuotedEmailText: message => message,
        globalConfig: { directUploadsEnabled: false },
        isOnAiNote: true,
        isOnPrivateNote: false,
        isPrivate: true,
        replyType: REPLY_EDITOR_MODES.AI_NOTE,
        setReplyToInPayload: item => item,
        toEmails: '',
      },
      'Hãy xử lý theo chính sách thanh toán hiện tại'
    );

    expect(payload).toMatchObject({
      conversationId: 123,
      message: 'Hãy xử lý theo chính sách thanh toán hiện tại',
      private: true,
      contentAttributes: {
        ai_note_for_agent: true,
        ai_note_source: 'reply_box',
      },
    });
  });

  it('allows AI note mode even when customer replies are restricted', () => {
    const dispatch = vi.fn();
    const context = {
      attachedFiles: [],
      currentChat: { can_reply: false },
      isAPIInbox: false,
      isAWhatsAppChannel: false,
      isRecordingAudio: false,
      replyType: REPLY_EDITOR_MODES.NOTE,
      $store: { dispatch },
      toggleAudioRecorder: vi.fn(),
    };

    ReplyBox.methods.setReplyMode.call(context, REPLY_EDITOR_MODES.AI_NOTE);

    expect(context.replyType).toBe(REPLY_EDITOR_MODES.AI_NOTE);
    expect(dispatch).toHaveBeenCalledWith('draftMessages/setReplyEditorMode', {
      mode: REPLY_EDITOR_MODES.AI_NOTE,
    });
  });
});
