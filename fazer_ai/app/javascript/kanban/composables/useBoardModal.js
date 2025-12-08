import { ref } from 'vue';
import { useStore } from 'vuex';

export function useBoardModal(options = {}) {
  const { onSuccess = null, onError = null } = options;

  const store = useStore();
  const showBoardModal = ref(false);
  const isSavingBoard = ref(false);

  const openBoardModal = () => {
    showBoardModal.value = true;
  };

  const closeBoardModal = () => {
    showBoardModal.value = false;
  };

  const saveBoard = async data => {
    isSavingBoard.value = true;
    try {
      const newBoard = await store.dispatch('kanban/createBoard', data);
      closeBoardModal();

      if (onSuccess) {
        await onSuccess(newBoard);
      }

      return newBoard;
    } catch (error) {
      if (onError) {
        onError(error);
      } else {
        throw error;
      }
    } finally {
      isSavingBoard.value = false;
    }
    return null;
  };

  return {
    showBoardModal,
    isSavingBoard,
    openBoardModal,
    closeBoardModal,
    saveBoard,
  };
}
