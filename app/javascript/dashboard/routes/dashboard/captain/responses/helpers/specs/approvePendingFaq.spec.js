import { approvePendingFaq } from '../approvePendingFaq';

describe('approvePendingFaq', () => {
  const t = vi.fn(key => key);
  const notify = vi.fn();
  const store = {
    dispatch: vi.fn(),
  };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('runs_full_flow_when_response_selected', async () => {
    const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    store.dispatch.mockResolvedValue({});

    const result = await approvePendingFaq({
      store,
      selectedResponse: { id: 42 },
      t,
      notify,
    });

    expect(result).toBe(true);
    expect(store.dispatch).toHaveBeenCalledWith('captainResponses/update', {
      id: 42,
      status: 'approved',
    });
    expect(logSpy.mock.calls).toEqual([
      ['[Captain Pending FAQ] Bắt đầu luồng'],
      ['[Captain Pending FAQ] Bước 1: Xác nhận FAQ cần duyệt'],
      ['[Captain Pending FAQ] Bước 2: Gửi yêu cầu duyệt FAQ'],
      ['[Captain Pending FAQ] Bước 3: Duyệt FAQ thành công'],
      ['[Captain Pending FAQ] Kết thúc luồng'],
    ]);
    expect(notify).toHaveBeenCalledWith(
      'CAPTAIN.RESPONSES.EDIT.APPROVE_SUCCESS_MESSAGE'
    );
    expect(warnSpy).not.toHaveBeenCalled();
    expect(errorSpy).not.toHaveBeenCalled();
  });

  it('uses_warning_branch_when_selected_response_missing', async () => {
    const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

    const result = await approvePendingFaq({
      store,
      selectedResponse: null,
      t,
      notify,
    });

    expect(result).toBe(false);
    expect(store.dispatch).not.toHaveBeenCalled();
    expect(warnSpy).toHaveBeenCalledWith(
      '[Captain Pending FAQ] Cảnh báo tại bước 1: Không có FAQ để duyệt'
    );
    expect(logSpy.mock.calls).toEqual([
      ['[Captain Pending FAQ] Bắt đầu luồng'],
      ['[Captain Pending FAQ] Kết thúc luồng'],
    ]);
    expect(notify).not.toHaveBeenCalled();
    expect(errorSpy).not.toHaveBeenCalled();
  });

  it('stops_flow_at_step_2_when_update_fails', async () => {
    const requestError = new Error('Approve failed');
    const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    store.dispatch.mockRejectedValueOnce(requestError);

    const result = await approvePendingFaq({
      store,
      selectedResponse: { id: 7 },
      t,
      notify,
    });

    expect(result).toBe(false);
    expect(store.dispatch).toHaveBeenCalledWith('captainResponses/update', {
      id: 7,
      status: 'approved',
    });
    expect(errorSpy).toHaveBeenCalledWith(
      '[Captain Pending FAQ] Lỗi tại bước 2: Không thể duyệt FAQ',
      requestError
    );
    expect(logSpy).not.toHaveBeenCalledWith(
      '[Captain Pending FAQ] Bước 3: Duyệt FAQ thành công'
    );
    expect(notify).toHaveBeenCalledWith('Approve failed');
    expect(warnSpy).not.toHaveBeenCalled();
    expect(logSpy).toHaveBeenLastCalledWith('[Captain Pending FAQ] Kết thúc luồng');
  });
});
