import { buildInboxData } from '../../inboxes/channelActions';

describe('#buildInboxData', () => {
  it('serializes inbox custom attributes as nested form data', () => {
    const formData = buildInboxData({
      name: 'Instagram Inbox',
      custom_attributes: {
        kimi_agent_name: 'instagram_sales',
      },
      channel: {
        webhook_url: 'https://example.test/webhook',
      },
    });

    expect(formData.get('custom_attributes[kimi_agent_name]')).toBe(
      'instagram_sales'
    );
    expect(formData.get('name')).toBe('Instagram Inbox');
    expect(formData.get('channel[webhook_url]')).toBe(
      'https://example.test/webhook'
    );
  });
});
