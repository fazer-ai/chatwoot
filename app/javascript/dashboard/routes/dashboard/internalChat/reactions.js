export const QUICK_EMOJIS = [
  { emoji: '👍', label: 'thumbs up' },
  { emoji: '❤️', label: 'heart' },
  { emoji: '😂', label: 'joy' },
  { emoji: '😮', label: 'surprised' },
  { emoji: '😢', label: 'sad' },
  { emoji: '🙏', label: 'pray' },
  { emoji: '🔥', label: 'fire' },
  { emoji: '🎉', label: 'party' },
];

export const findOwnReaction = (reactions, emoji, userId) =>
  reactions.find(r => r.emoji === emoji && r.user_id === userId) || null;
