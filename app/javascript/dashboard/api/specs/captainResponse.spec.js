import CaptainResponsesAPI from '../captain/response';
import ApiClient from '../ApiClient';

describe('#CaptainResponsesAPI', () => {
  it('creates correct instance', () => {
    expect(CaptainResponsesAPI).toBeInstanceOf(ApiClient);
    expect(CaptainResponsesAPI).toHaveProperty('get');
    expect(CaptainResponsesAPI).toHaveProperty('show');
    expect(CaptainResponsesAPI).toHaveProperty('create');
    expect(CaptainResponsesAPI).toHaveProperty('update');
    expect(CaptainResponsesAPI).toHaveProperty('delete');
    expect(CaptainResponsesAPI).toHaveProperty('scanAnswer');
    expect(CaptainResponsesAPI).toHaveProperty('scanAllPending');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const originalPathname = window.location.pathname;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve()),
      get: vi.fn(() => Promise.resolve()),
      patch: vi.fn(() => Promise.resolve()),
      delete: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
      window.history.replaceState(
        {},
        '',
        '/app/accounts/5/captain/1/faqs?page=1'
      );
    });

    afterEach(() => {
      window.axios = originalAxios;
      window.history.replaceState({}, '', originalPathname || '/');
    });

    it('wraps create payload under assistant_response', () => {
      CaptainResponsesAPI.create({
        question: 'How to reset password?',
        answer: 'Use forgot password',
        assistant_id: 1,
      });

      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/accounts/5/captain/assistant_responses',
        {
          assistant_response: {
            question: 'How to reset password?',
            answer: 'Use forgot password',
            assistant_id: 1,
          },
        }
      );
    });

    it('wraps update payload under assistant_response', () => {
      CaptainResponsesAPI.update(42, {
        status: 'approved',
      });

      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/5/captain/assistant_responses/42',
        {
          assistant_response: {
            status: 'approved',
          },
        }
      );
    });
  });
});
