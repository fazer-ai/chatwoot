import KanbanAPI from '../kanban';

describe('#KanbanAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
    put: vi.fn(() => Promise.resolve()),
  };

  beforeEach(() => {
    window.axios = axiosMock;
  });

  afterEach(() => {
    window.axios = originalAxios;
    vi.clearAllMocks();
  });

  it('loads the board with filters', () => {
    KanbanAPI.getConversations({ inbox_id: 3 });

    expect(axiosMock.get).toHaveBeenCalledWith('/api/v1/kanban', {
      params: { inbox_id: 3 },
    });
  });

  it('moves a conversation to another stage', () => {
    KanbanAPI.moveConversation(42, 'qualificado');

    expect(axiosMock.put).toHaveBeenCalledWith('/api/v1/kanban/42/move', {
      status: 'qualificado',
    });
  });

  it('exports a filtered column', () => {
    KanbanAPI.exportConversations({ status: 'convertido' });

    expect(axiosMock.get).toHaveBeenCalledWith('/api/v1/kanban/export', {
      params: { status: 'convertido' },
    });
  });
});
