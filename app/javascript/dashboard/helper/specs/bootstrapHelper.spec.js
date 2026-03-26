import { getConversationDisplayPreferencePatch } from 'dashboard/helper/bootstrapHelper';

describe('getConversationDisplayPreferencePatch', () => {
  it('returns an expanded layout update on small screens when needed', () => {
    expect(
      getConversationDisplayPreferencePatch({
        isSmallScreen: true,
        currentDisplayType: 'condensed',
        expandedLayoutType: 'expanded',
        previousDisplayType: 'condensed',
      })
    ).toEqual({
      conversation_display_type: 'expanded',
    });
  });

  it('returns null when the small screen layout already matches', () => {
    expect(
      getConversationDisplayPreferencePatch({
        isSmallScreen: true,
        currentDisplayType: 'expanded',
        expandedLayoutType: 'expanded',
        previousDisplayType: 'condensed',
      })
    ).toBeNull();
  });

  it('restores the previous layout on large screens when available', () => {
    expect(
      getConversationDisplayPreferencePatch({
        isSmallScreen: false,
        currentDisplayType: 'expanded',
        expandedLayoutType: 'expanded',
        previousDisplayType: 'condensed',
      })
    ).toEqual({
      conversation_display_type: 'condensed',
    });
  });

  it('returns null when there is no previous layout to restore', () => {
    expect(
      getConversationDisplayPreferencePatch({
        isSmallScreen: false,
        currentDisplayType: 'expanded',
        expandedLayoutType: 'expanded',
        previousDisplayType: undefined,
      })
    ).toBeNull();
  });
});
