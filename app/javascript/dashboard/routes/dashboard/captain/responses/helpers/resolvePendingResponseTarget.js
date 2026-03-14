export const resolvePendingResponseTarget = ({
  response,
  responseId,
  responses,
}) => {
  console.log('[Captain Pending] Bước 1: Bắt đầu tìm FAQ cho action', {
    responseId,
    hasInlineResponse: Boolean(response?.id),
  });

  if (response?.id) {
    console.log('[Captain Pending] Bước 2: Dùng trực tiếp FAQ từ card', {
      responseId: Number(response.id),
    });
    return response;
  }

  if (!responseId) {
    console.warn('[Captain Pending] Cảnh báo: Action không có id FAQ');
    return null;
  }

  const matchedResponse =
    responses.find(item => Number(item.id) === Number(responseId)) || null;

  if (!matchedResponse) {
    console.warn('[Captain Pending] Cảnh báo: Không tìm thấy FAQ theo id', {
      responseId,
    });
    return null;
  }

  console.log('[Captain Pending] Bước 2: Tìm thấy FAQ theo id', {
    responseId,
  });
  return matchedResponse;
};
