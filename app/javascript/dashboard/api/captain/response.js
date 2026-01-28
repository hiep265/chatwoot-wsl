/* global axios */
import ApiClient from '../ApiClient';

class CaptainResponses extends ApiClient {
  constructor() {
    super('captain/assistant_responses', { accountScoped: true });
  }

  get({ page = 1, search, assistantId, documentId, status } = {}) {
    return axios.get(this.url, {
      params: {
        page,
        search,
        assistant_id: assistantId,
        document_id: documentId,
        status,
      },
    });
  }

  // Scan answer cho một FAQ từ conversation gốc
  scanAnswer(id) {
    return axios.post(`${this.url}/${id}/scan_answer`);
  }

  // Scan all pending FAQs
  scanAllPending({ assistantId } = {}) {
    return axios.post(`${this.url}/scan_all_pending`, {
      assistant_id: assistantId,
    });
  }
}

export default new CaptainResponses();
