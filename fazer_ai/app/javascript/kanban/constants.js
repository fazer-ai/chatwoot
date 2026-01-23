export const KANBAN_PRIORITIES = [
  {
    id: 'urgent',
    icon: 'i-lucide-chevrons-up',
    color: '#EF4444',
  },
  {
    id: 'high',
    icon: 'i-lucide-chevron-up',
    color: '#F59E0B',
  },
  {
    id: 'medium',
    icon: 'i-lucide-equal',
    color: '#3B82F6',
  },
  {
    id: 'low',
    icon: 'i-lucide-chevron-down',
    color: '#64748B',
  },
  {
    id: null,
    icon: 'i-lucide-minus',
    color: '#94A3B8',
  },
];

export const KANBAN_COLUMN_WIDTH_STYLES = {
  width: 'calc((100% - 4rem) / 4)',
  maxWidth: '350px',
  minWidth: '280px',
};

export const BOARD_TEMPLATES = [
  {
    id: 'sales',
    icon: 'i-lucide-badge-dollar-sign',
    nameKey: 'KANBAN_TEMPLATES.SALES.NAME',
    descriptionKey: 'KANBAN_TEMPLATES.SALES.DESCRIPTION',
    steps_attributes: [
      {
        nameKey: 'KANBAN_TEMPLATES.SALES.STEPS.NEW_LEAD',
        color: '#94a3b8',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.SALES.TASKS.NEW_LEAD',
            priority: 'high',
            descriptionKey: 'KANBAN_TEMPLATES.SALES.TASKS.NEW_LEAD_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.SALES.STEPS.QUALIFYING',
        color: '#60a5fa',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.SALES.TASKS.QUALIFY_LEAD',
            priority: 'medium',
            descriptionKey: 'KANBAN_TEMPLATES.SALES.TASKS.QUALIFY_LEAD_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.SALES.STEPS.PROPOSAL_SENT',
        color: '#a78bfa',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.SALES.TASKS.SEND_PROPOSAL',
            priority: 'high',
            descriptionKey: 'KANBAN_TEMPLATES.SALES.TASKS.SEND_PROPOSAL_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.SALES.STEPS.NEGOTIATION',
        color: '#fbbf24',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.SALES.TASKS.NEGOTIATE',
            priority: 'urgent',
            descriptionKey: 'KANBAN_TEMPLATES.SALES.TASKS.NEGOTIATE_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.SALES.STEPS.LOST',
        color: '#ef4444',
        cancelled: true,
        tasks_attributes: [],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.SALES.STEPS.WON',
        color: '#34d399',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.SALES.TASKS.CLOSE_DEAL',
            priority: 'high',
            descriptionKey: 'KANBAN_TEMPLATES.SALES.TASKS.CLOSE_DEAL_DESC',
          },
        ],
      },
    ],
  },
  {
    id: 'support',
    icon: 'i-lucide-headphones',
    nameKey: 'KANBAN_TEMPLATES.SUPPORT.NAME',
    descriptionKey: 'KANBAN_TEMPLATES.SUPPORT.DESCRIPTION',
    steps_attributes: [
      {
        nameKey: 'KANBAN_TEMPLATES.SUPPORT.STEPS.NEW_TICKET',
        color: '#94a3b8',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.SUPPORT.TASKS.BUG_REPORT',
            priority: 'high',
            descriptionKey: 'KANBAN_TEMPLATES.SUPPORT.TASKS.BUG_REPORT_DESC',
          },
          {
            titleKey: 'KANBAN_TEMPLATES.SUPPORT.TASKS.FEATURE_REQUEST',
            priority: 'low',
            descriptionKey:
              'KANBAN_TEMPLATES.SUPPORT.TASKS.FEATURE_REQUEST_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.SUPPORT.STEPS.IN_ANALYSIS',
        color: '#60a5fa',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.SUPPORT.TASKS.BILLING_ISSUE',
            priority: 'medium',
            descriptionKey: 'KANBAN_TEMPLATES.SUPPORT.TASKS.BILLING_ISSUE_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.SUPPORT.STEPS.WAITING_CUSTOMER',
        color: '#fbbf24',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.SUPPORT.TASKS.FOLLOW_UP',
            priority: null,
            descriptionKey: 'KANBAN_TEMPLATES.SUPPORT.TASKS.FOLLOW_UP_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.SUPPORT.STEPS.IN_PROGRESS',
        color: '#a78bfa',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.SUPPORT.TASKS.INTEGRATION_HELP',
            priority: 'urgent',
            descriptionKey:
              'KANBAN_TEMPLATES.SUPPORT.TASKS.INTEGRATION_HELP_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.SUPPORT.STEPS.RESOLVED',
        color: '#34d399',
        tasks_attributes: [],
      },
    ],
  },
  {
    id: 'recruitment',
    icon: 'i-lucide-users',
    nameKey: 'KANBAN_TEMPLATES.RECRUITMENT.NAME',
    descriptionKey: 'KANBAN_TEMPLATES.RECRUITMENT.DESCRIPTION',
    steps_attributes: [
      {
        nameKey: 'KANBAN_TEMPLATES.RECRUITMENT.STEPS.APPLIED',
        color: '#94a3b8',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.RECRUITMENT.TASKS.REVIEW_RESUME',
            priority: null,
            descriptionKey:
              'KANBAN_TEMPLATES.RECRUITMENT.TASKS.REVIEW_RESUME_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.RECRUITMENT.STEPS.SCREENING',
        color: '#60a5fa',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.RECRUITMENT.TASKS.PHONE_SCREEN',
            priority: 'medium',
            descriptionKey:
              'KANBAN_TEMPLATES.RECRUITMENT.TASKS.PHONE_SCREEN_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.RECRUITMENT.STEPS.INTERVIEW',
        color: '#a78bfa',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.RECRUITMENT.TASKS.TECHNICAL_INTERVIEW',
            priority: 'high',
            descriptionKey:
              'KANBAN_TEMPLATES.RECRUITMENT.TASKS.TECHNICAL_INTERVIEW_DESC',
          },
          {
            titleKey: 'KANBAN_TEMPLATES.RECRUITMENT.TASKS.FINAL_INTERVIEW',
            priority: 'urgent',
            descriptionKey:
              'KANBAN_TEMPLATES.RECRUITMENT.TASKS.FINAL_INTERVIEW_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.RECRUITMENT.STEPS.OFFER',
        color: '#fbbf24',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.RECRUITMENT.TASKS.DRAFT_OFFER',
            priority: 'high',
            descriptionKey:
              'KANBAN_TEMPLATES.RECRUITMENT.TASKS.DRAFT_OFFER_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.RECRUITMENT.STEPS.REJECTED',
        color: '#ef4444',
        cancelled: true,
        tasks_attributes: [],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.RECRUITMENT.STEPS.HIRED',
        color: '#34d399',
        tasks_attributes: [],
      },
    ],
  },
];
