import disparos from '../disparos';
import ApiClient from '../ApiClient';

describe('#DisparosAPI', () => {
  it('creates correct instance', () => {
    expect(disparos).toBeInstanceOf(ApiClient);
    expect(disparos).toHaveProperty('get');
    expect(disparos).toHaveProperty('show');
    expect(disparos).toHaveProperty('create');
    expect(disparos).toHaveProperty('dryRun');
    expect(disparos).toHaveProperty('shadowRun');
    expect(disparos).toHaveProperty('getTargets');
    expect(disparos.url).toBe('/api/v1/disparos');
  });

  describe('member routes', () => {
    beforeEach(() => {
      global.axios = {
        post: vi.fn(() => Promise.resolve()),
        get: vi.fn(() => Promise.resolve()),
      };
    });

    it('#dryRun posts to the dry_run member route', () => {
      disparos.dryRun(7);
      expect(global.axios.post).toHaveBeenCalledWith(
        '/api/v1/disparos/7/dry_run'
      );
    });

    it('#shadowRun posts to the shadow_run member route', () => {
      disparos.shadowRun(7);
      expect(global.axios.post).toHaveBeenCalledWith(
        '/api/v1/disparos/7/shadow_run'
      );
    });

    it('#getTargets gets the targets member route with page param', () => {
      disparos.getTargets(7, 2);
      expect(global.axios.get).toHaveBeenCalledWith(
        '/api/v1/disparos/7/targets',
        {
          params: { page: 2 },
        }
      );
    });
  });
});
