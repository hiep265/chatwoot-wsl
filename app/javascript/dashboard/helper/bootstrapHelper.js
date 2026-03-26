export const getConversationDisplayPreferencePatch = ({
  isSmallScreen,
  currentDisplayType,
  expandedLayoutType,
  previousDisplayType,
}) => {
  if (isSmallScreen) {
    if (currentDisplayType === expandedLayoutType) {
      return null;
    }

    return {
      conversation_display_type: expandedLayoutType,
    };
  }

  if (!previousDisplayType || previousDisplayType === currentDisplayType) {
    return null;
  }

  return {
    conversation_display_type: previousDisplayType,
  };
};
