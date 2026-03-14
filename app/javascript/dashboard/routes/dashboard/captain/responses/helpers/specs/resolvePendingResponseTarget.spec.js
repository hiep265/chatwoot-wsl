import { resolvePendingResponseTarget } from '../resolvePendingResponseTarget';

describe('resolvePendingResponseTarget', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('prefers_inline_response_from_card', () => {
    const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const response = { id: 42, question: 'FAQ inline' };

    const result = resolvePendingResponseTarget({
      response,
      responseId: 42,
      responses: [{ id: 1 }, response],
    });

    expect(result).toBe(response);
    expect(logSpy.mock.calls).toEqual([
      [
        '[Captain Pending] Bước 1: Bắt đầu tìm FAQ cho action',
        { responseId: 42, hasInlineResponse: true },
      ],
      [
        '[Captain Pending] Bước 2: Dùng trực tiếp FAQ từ card',
        { responseId: 42 },
      ],
    ]);
    expect(warnSpy).not.toHaveBeenCalled();
  });

  it('falls_back_to_lookup_by_id', () => {
    const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

    const result = resolvePendingResponseTarget({
      response: null,
      responseId: 7,
      responses: [{ id: 4 }, { id: 7, question: 'FAQ lookup' }],
    });

    expect(result).toEqual({ id: 7, question: 'FAQ lookup' });
    expect(logSpy.mock.calls).toEqual([
      [
        '[Captain Pending] Bước 1: Bắt đầu tìm FAQ cho action',
        { responseId: 7, hasInlineResponse: false },
      ],
      [
        '[Captain Pending] Bước 2: Tìm thấy FAQ theo id',
        { responseId: 7 },
      ],
    ]);
    expect(warnSpy).not.toHaveBeenCalled();
  });

  it('stops_early_when_response_cannot_be_resolved', () => {
    const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

    const result = resolvePendingResponseTarget({
      response: null,
      responseId: 9,
      responses: [{ id: 4 }, { id: 7 }],
    });

    expect(result).toBeNull();
    expect(logSpy).toHaveBeenCalledWith(
      '[Captain Pending] Bước 1: Bắt đầu tìm FAQ cho action',
      { responseId: 9, hasInlineResponse: false }
    );
    expect(warnSpy).toHaveBeenCalledWith(
      '[Captain Pending] Cảnh báo: Không tìm thấy FAQ theo id',
      { responseId: 9 }
    );
  });
});
