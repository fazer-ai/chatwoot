/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class TasksAPI extends ApiClient {
  constructor() {
    super('kanban/tasks', { accountScoped: true, apiVersion: 'v1' });
  }

  get(params) {
    return axios.get(this.url, { params });
  }

  getByStep(
    stepId,
    { page = 1, perPage = 25, sort, order, agentId, inboxId } = {}
  ) {
    return axios.get(this.url, {
      params: {
        board_step_id: stepId,
        page,
        per_page: perPage,
        sort,
        order,
        agent_id: agentId,
        inbox_id: inboxId,
      },
    });
  }

  create(data) {
    return axios.post(this.url, data);
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, data);
  }

  move(id, data) {
    return axios.post(`${this.url}/${id}/move`, data);
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new TasksAPI();
