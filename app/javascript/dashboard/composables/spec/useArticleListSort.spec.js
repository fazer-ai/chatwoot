import { ref } from 'vue';
import { useArticleListSort } from 'dashboard/composables/useArticleListSort';

const mockDispatch = vi.fn();
const uiSettings = ref({});

vi.mock('dashboard/composables/store', () => ({
  useStoreGetters: () => ({ getUISettings: uiSettings }),
  useStore: () => ({ dispatch: mockDispatch }),
}));

describe('useArticleListSort', () => {
  beforeEach(() => {
    mockDispatch.mockClear();
    uiSettings.value = { editor_message_key: 'enter' };
  });

  it('starts from the last updated first when nothing was chosen', () => {
    const { sort, sortField, sortOrder } = useArticleListSort();

    expect(sort.value).toBe('-updated_at');
    expect(sortField.value).toBe('updated_at');
    expect(sortOrder.value).toBe('-');
  });

  it('reads the order the user chose', () => {
    uiSettings.value.help_center_articles_sort_by = 'title';
    const { sort, sortField, sortOrder } = useArticleListSort();

    expect(sort.value).toBe('title');
    expect(sortField.value).toBe('title');
    expect(sortOrder.value).toBe('');
  });

  // The API turns these down, so sending one would leave the tab without articles.
  it.each(['position', '-', '--views', 'title desc', 42, null])(
    'falls back to the default for a saved value the API does not take (%s)',
    value => {
      uiSettings.value.help_center_articles_sort_by = value;

      expect(useArticleListSort().sort.value).toBe('-updated_at');
    }
  );

  it('saves the choice next to the other UI settings', () => {
    useArticleListSort().setSort({ field: 'created_at', order: '-' });

    expect(mockDispatch).toHaveBeenCalledWith('updateUISettings', {
      uiSettings: {
        editor_message_key: 'enter',
        help_center_articles_sort_by: '-created_at',
      },
    });
  });
});
