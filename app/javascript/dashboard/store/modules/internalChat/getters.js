export const getters = {
  getChannels: _state => {
    return Object.values(_state.records).sort((a, b) => {
      const nameA = (a.name || '').toLowerCase();
      const nameB = (b.name || '').toLowerCase();
      return nameA.localeCompare(nameB);
    });
  },

  getChannelById: _state => channelId => {
    return (
      _state.records[channelId] || _state.archivedRecords[channelId] || null
    );
  },

  getChannelsByCategory: _state => categoryId => {
    return Object.values(_state.records)
      .filter(
        channel =>
          channel.category_id === categoryId &&
          !channel.is_dm &&
          channel.channel_type !== 'dm' &&
          channel.status !== 'archived'
      )
      .sort((a, b) => {
        const nameA = (a.name || '').toLowerCase();
        const nameB = (b.name || '').toLowerCase();
        return nameA.localeCompare(nameB);
      });
  },

  getDMChannels: _state => {
    return Object.values(_state.records)
      .filter(
        channel =>
          (channel.is_dm || channel.channel_type === 'dm') &&
          channel.status !== 'archived'
      )
      .sort((a, b) => {
        const tsA = a.last_activity_at || 0;
        const tsB = b.last_activity_at || 0;
        if (tsA !== tsB) return tsB - tsA;
        return (a.id || 0) - (b.id || 0);
      });
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

  getArchivedChannels: _state => {
    return Object.values(_state.archivedRecords).sort((a, b) => {
      const nameA = (a.name || '').toLowerCase();
      const nameB = (b.name || '').toLowerCase();
      return nameA.localeCompare(nameB);
    });
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
