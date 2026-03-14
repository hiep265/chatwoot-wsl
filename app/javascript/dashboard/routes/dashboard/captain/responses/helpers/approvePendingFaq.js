export const approvePendingFaq = async ({
  store,
  selectedResponse,
  t,
  notify,
}) => {
  console.log('[Captain Pending FAQ] Bắt đầu luồng');

  if (!selectedResponse?.id) {
    console.warn(
      '[Captain Pending FAQ] Cảnh báo tại bước 1: Không có FAQ để duyệt'
    );
    console.log('[Captain Pending FAQ] Kết thúc luồng');
    return false;
  }

  console.log('[Captain Pending FAQ] Bước 1: Xác nhận FAQ cần duyệt');

  try {
    console.log('[Captain Pending FAQ] Bước 2: Gửi yêu cầu duyệt FAQ');
    await store.dispatch('captainResponses/update', {
      id: selectedResponse.id,
      status: 'approved',
    });
    console.log('[Captain Pending FAQ] Bước 3: Duyệt FAQ thành công');
    notify(t('CAPTAIN.RESPONSES.EDIT.APPROVE_SUCCESS_MESSAGE'));
    return true;
  } catch (error) {
    const errorMessage =
      error?.message || t('CAPTAIN.RESPONSES.EDIT.ERROR_MESSAGE');
    console.error(
      '[Captain Pending FAQ] Lỗi tại bước 2: Không thể duyệt FAQ',
      error
    );
    notify(errorMessage);
    return false;
  } finally {
    console.log('[Captain Pending FAQ] Kết thúc luồng');
  }
};
