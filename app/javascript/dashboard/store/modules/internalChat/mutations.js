export const mutations = {
  SET_CHANNELS(_state, channels) {
    const records = {};
    channels.forEach(channel => {
      records[channel.id] = channel;
    });
    _state.records = records;
  },

  ADD_CHANNEL(_state, channel) {
    _state.records = {
      ..._state.records,
      [channel.id]: channel,
    };
  },

  UPDATE_CHANNEL(_state, channel) {
    const existing = _state.records[channel.id];
    if (existing) {
      _state.records = {
        ..._state.records,
        [channel.id]: { ...existing, ...channel },
      };
    }
  },

  DELETE_CHANNEL(_state, channelId) {
    const { [channelId]: _, ...rest } = _state.records;
    _state.records = rest;
    if (_state.activeChannelId === channelId) {
      _state.activeChannelId = null;
    }
  },

  SET_CATEGORIES(_state, categories) {
    _state.categories = categories;
  },

  SET_UI_FLAG(_state, flags) {
    _state.uiFlags = { ..._state.uiFlags, ...flags };
  },

  SET_ACTIVE_CHANNEL(_state, channelId) {
    _state.activeChannelId = channelId;
  },
};

export default mutations;
