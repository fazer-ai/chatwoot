export const getters = {
  getChannels: _state => {
    return Object.values(_state.records).sort((a, b) => {
      const nameA = (a.name || '').toLowerCase();
      const nameB = (b.name || '').toLowerCase();
      return nameA.localeCompare(nameB);
    });
  },

  getChannelById: _state => channelId => {
    return _state.records[channelId] || null;
  },

  getChannelsByCategory: _state => categoryId => {
    return Object.values(_state.records).filter(
      channel =>
        channel.category_id === categoryId &&
        !channel.is_dm &&
        channel.channel_type !== 'dm' &&
        channel.status !== 'archived'
    );
  },

  getDMChannels: _state => {
    return Object.values(_state.records).filter(
      channel =>
        (channel.is_dm || channel.channel_type === 'dm') &&
        channel.status !== 'archived'
    );
  },

  getFavoriteChannels: _state => {
    return Object.values(_state.records).filter(
      channel => channel.favorited && channel.status !== 'archived'
    );
  },

  getMutedChannels: _state => {
    return Object.values(_state.records).filter(
      channel => channel.muted && channel.status !== 'archived'
    );
  },

  getCategories: _state => {
    return _state.categories;
  },

  getUnreadCount: _state => {
    return Object.values(_state.records).reduce((total, channel) => {
      if (channel.muted) return total;
      return total + (channel.unread_count || 0);
    }, 0);
  },

  getUIFlags: _state => {
    return _state.uiFlags;
  },

  getActiveChannelId: _state => {
    return _state.activeChannelId;
  },
};

export default getters;
