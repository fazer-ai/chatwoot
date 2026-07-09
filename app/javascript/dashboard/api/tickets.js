/* global axios */

import ApiClient from './ApiClient';

class Tickets extends ApiClient {
  constructor() {
    super('tickets', { accountScoped: true });
  }

  // POST /api/v1/accounts/:account_id/tickets
  // params: { message_id, relatar_problema, comportamento_esperado, attachments: [File] }
  // When attachments are present we use multipart/form-data so the Rails
  // controller reads them as ActionDispatch::Http::UploadedFile via
  // `params[:attachments]`. Without attachments a plain JSON body is fine.
  create({
    messageId,
    relatarProblema,
    comportamentoEsperado,
    attachments = [],
  }) {
    if (attachments.length === 0) {
      return axios.post(this.url, {
        message_id: messageId,
        relatar_problema: relatarProblema,
        comportamento_esperado: comportamentoEsperado,
      });
    }

    const form = new FormData();
    form.append('message_id', messageId);
    form.append('relatar_problema', relatarProblema);
    if (comportamentoEsperado) {
      form.append('comportamento_esperado', comportamentoEsperado);
    }
    attachments.forEach(file => form.append('attachments[]', file));

    return axios.post(this.url, form, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  addComment(id, { comment }) {
    return axios.post(`${this.url}/${id}/add_comment`, { comment });
  }
}

export default new Tickets();
