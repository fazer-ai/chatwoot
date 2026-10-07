import axios from 'axios';
import { actions } from '../actions';

global.axios = axios;
vi.mock('axios');

// The order the Articles tab asks for (#811) has to reach the request, or the list keeps
// coming back by last update whatever the menu says.
describe('#index with an order', () => {
  it('asks the API for the order it was given', async () => {
    axios.get.mockResolvedValue({ data: { payload: [], meta: {} } });

    await actions.index(
      { commit: vi.fn() },
      { pageNumber: 2, portalSlug: 'docs', locale: 'en', sort: '-created_at' }
    );

    const url = new URL(axios.get.mock.calls[0][0], 'http://localhost');
    expect(url.searchParams.get('sort')).toBe('-created_at');
    expect(url.searchParams.get('page')).toBe('2');
  });

  // The page cancels a request once a newer one starts; the cancelled one must not touch the list.
  it('leaves the store alone when its request was cancelled', async () => {
    const controller = new AbortController();
    const commit = vi.fn();
    axios.get.mockImplementation(() => {
      controller.abort();
      return Promise.reject(
        Object.assign(new Error('canceled'), { code: 'ERR_CANCELED' })
      );
    });

    await expect(
      actions.index(
        { commit },
        { portalSlug: 'docs', sort: 'title', signal: controller.signal }
      )
    ).rejects.toThrow();

    expect(axios.get.mock.calls[0][1]).toEqual({ signal: controller.signal });
    expect(commit.mock.calls).toEqual([
      [expect.anything(), { isFetching: true }],
    ]);
  });
});
