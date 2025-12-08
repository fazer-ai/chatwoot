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
    id: 'normal',
    icon: 'i-lucide-equal',
    color: '#3B82F6',
  },
  {
    id: 'low',
    icon: 'i-lucide-chevron-down',
    color: '#64748B',
  },
];

export const KANBAN_COLUMN_WIDTH_STYLES = {
  width: 'calc((100% - 4rem) / 4)',
  maxWidth: '350px',
  minWidth: '300px',
};

export const BOARD_TEMPLATES = [
  {
    id: 'sales',
    icon: 'i-lucide-badge-dollar-sign',
    nameKey: 'KANBAN_TEMPLATES.SALES.NAME',
    descriptionKey: 'KANBAN_TEMPLATES.SALES.DESCRIPTION',
    steps_attributes: [
      {
        nameKey: 'KANBAN_TEMPLATES.SALES.STEPS.LEAD_IN',
        color: '#94a3b8',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.SALES.TASKS.NEW_LEAD',
            priority: 'high',
            descriptionKey: 'KANBAN_TEMPLATES.SALES.TASKS.NEW_LEAD_DESC',
          },
          {
            titleKey: 'KANBAN_TEMPLATES.SALES.TASKS.FOLLOW_UP',
            priority: 'normal',
            descriptionKey: 'KANBAN_TEMPLATES.SALES.TASKS.FOLLOW_UP_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.SALES.STEPS.CONTACTED',
        color: '#60a5fa',
        tasks_attributes: [],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.SALES.STEPS.DEMO_SCHEDULED',
        color: '#fbbf24',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.SALES.TASKS.DEMO',
            priority: 'urgent',
            descriptionKey: 'KANBAN_TEMPLATES.SALES.TASKS.DEMO_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.SALES.STEPS.PROPOSAL_SENT',
        color: '#a78bfa',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.SALES.TASKS.CONTRACT_DRAFT',
            priority: 'high',
            descriptionKey: 'KANBAN_TEMPLATES.SALES.TASKS.CONTRACT_DRAFT_DESC',
          },
          {
            titleKey: 'KANBAN_TEMPLATES.SALES.TASKS.PRICING_REVIEW',
            priority: 'normal',
            descriptionKey: 'KANBAN_TEMPLATES.SALES.TASKS.PRICING_REVIEW_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.SALES.STEPS.NEGOTIATION',
        color: '#f472b6',
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
        color: '#9ca3af',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.RECRUITMENT.TASKS.SOURCING',
            priority: 'normal',
            descriptionKey: 'KANBAN_TEMPLATES.RECRUITMENT.TASKS.SOURCING_DESC',
          },
          {
            titleKey: 'KANBAN_TEMPLATES.RECRUITMENT.TASKS.REVIEW_RESUME',
            priority: 'normal',
            descriptionKey:
              'KANBAN_TEMPLATES.RECRUITMENT.TASKS.REVIEW_RESUME_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.RECRUITMENT.STEPS.SCREENING',
        color: '#38bdf8',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.RECRUITMENT.TASKS.PHONE_SCREEN',
            priority: 'high',
            descriptionKey:
              'KANBAN_TEMPLATES.RECRUITMENT.TASKS.PHONE_SCREEN_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.RECRUITMENT.STEPS.INTERVIEW',
        color: '#818cf8',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.RECRUITMENT.TASKS.ONSITE',
            priority: 'urgent',
            descriptionKey: 'KANBAN_TEMPLATES.RECRUITMENT.TASKS.ONSITE_DESC',
          },
          {
            titleKey: 'KANBAN_TEMPLATES.RECRUITMENT.TASKS.CHECK_REFS',
            priority: 'normal',
            descriptionKey:
              'KANBAN_TEMPLATES.RECRUITMENT.TASKS.CHECK_REFS_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.RECRUITMENT.STEPS.OFFER',
        color: '#c084fc',
        tasks_attributes: [],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.RECRUITMENT.STEPS.HIRED',
        color: '#34d399',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.RECRUITMENT.TASKS.DRAFT_OFFER',
            priority: 'high',
            descriptionKey:
              'KANBAN_TEMPLATES.RECRUITMENT.TASKS.DRAFT_OFFER_DESC',
          },
        ],
      },
    ],
  },
  {
    id: 'roadmap',
    icon: 'i-lucide-map',
    nameKey: 'KANBAN_TEMPLATES.ROADMAP.NAME',
    descriptionKey: 'KANBAN_TEMPLATES.ROADMAP.DESCRIPTION',
    steps_attributes: [
      {
        nameKey: 'KANBAN_TEMPLATES.ROADMAP.STEPS.BACKLOG',
        color: '#a1a1aa',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.ROADMAP.TASKS.DARK_MODE',
            priority: 'low',
            descriptionKey: 'KANBAN_TEMPLATES.ROADMAP.TASKS.DARK_MODE_DESC',
          },
          {
            titleKey: 'KANBAN_TEMPLATES.ROADMAP.TASKS.USER_ROLES',
            priority: 'high',
            descriptionKey: 'KANBAN_TEMPLATES.ROADMAP.TASKS.USER_ROLES_DESC',
          },
          {
            titleKey: 'KANBAN_TEMPLATES.ROADMAP.TASKS.MOBILE_APP',
            priority: 'normal',
            descriptionKey: 'KANBAN_TEMPLATES.ROADMAP.TASKS.MOBILE_APP_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.ROADMAP.STEPS.NEXT_UP',
        color: '#22d3ee',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.ROADMAP.TASKS.API_V2',
            priority: 'high',
            descriptionKey: 'KANBAN_TEMPLATES.ROADMAP.TASKS.API_V2_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.ROADMAP.STEPS.IN_PROGRESS',
        color: '#fb923c',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.ROADMAP.TASKS.LOGIN_BUG',
            priority: 'urgent',
            descriptionKey: 'KANBAN_TEMPLATES.ROADMAP.TASKS.LOGIN_BUG_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.ROADMAP.STEPS.TESTING',
        color: '#a3e635',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.ROADMAP.TASKS.PERF_OPT',
            priority: 'normal',
            descriptionKey: 'KANBAN_TEMPLATES.ROADMAP.TASKS.PERF_OPT_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.ROADMAP.STEPS.RELEASED',
        color: '#4ade80',
        tasks_attributes: [],
      },
    ],
  },
  {
    id: 'content',
    icon: 'i-lucide-calendar',
    nameKey: 'KANBAN_TEMPLATES.CONTENT.NAME',
    descriptionKey: 'KANBAN_TEMPLATES.CONTENT.DESCRIPTION',
    steps_attributes: [
      {
        nameKey: 'KANBAN_TEMPLATES.CONTENT.STEPS.IDEAS',
        color: '#a8a29e',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.CONTENT.TASKS.BLOG_TIPS',
            priority: 'low',
            descriptionKey: 'KANBAN_TEMPLATES.CONTENT.TASKS.BLOG_TIPS_DESC',
          },
          {
            titleKey: 'KANBAN_TEMPLATES.CONTENT.TASKS.WEBINAR',
            priority: 'normal',
            descriptionKey: 'KANBAN_TEMPLATES.CONTENT.TASKS.WEBINAR_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.CONTENT.STEPS.DRAFTING',
        color: '#2dd4bf',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.CONTENT.TASKS.NEWSLETTER',
            priority: 'normal',
            descriptionKey: 'KANBAN_TEMPLATES.CONTENT.TASKS.NEWSLETTER_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.CONTENT.STEPS.REVIEW',
        color: '#facc15',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.CONTENT.TASKS.SOCIAL_LAUNCH',
            priority: 'high',
            descriptionKey: 'KANBAN_TEMPLATES.CONTENT.TASKS.SOCIAL_LAUNCH_DESC',
          },
          {
            titleKey: 'KANBAN_TEMPLATES.CONTENT.TASKS.CASE_STUDY',
            priority: 'normal',
            descriptionKey: 'KANBAN_TEMPLATES.CONTENT.TASKS.CASE_STUDY_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.CONTENT.STEPS.SCHEDULED',
        color: '#e879f9',
        tasks_attributes: [],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.CONTENT.STEPS.PUBLISHED',
        color: '#fb7185',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.CONTENT.TASKS.VIDEO_TUTORIAL',
            priority: 'high',
            descriptionKey:
              'KANBAN_TEMPLATES.CONTENT.TASKS.VIDEO_TUTORIAL_DESC',
          },
        ],
      },
    ],
  },
  {
    id: 'project',
    icon: 'i-lucide-briefcase',
    nameKey: 'KANBAN_TEMPLATES.PROJECT.NAME',
    descriptionKey: 'KANBAN_TEMPLATES.PROJECT.DESCRIPTION',
    steps_attributes: [
      {
        nameKey: 'KANBAN_TEMPLATES.PROJECT.STEPS.TO_DO',
        color: '#a3a3a3',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.PROJECT.TASKS.SETUP_ENV',
            priority: 'high',
            descriptionKey: 'KANBAN_TEMPLATES.PROJECT.TASKS.SETUP_ENV_DESC',
          },
          {
            titleKey: 'KANBAN_TEMPLATES.PROJECT.TASKS.WRITE_DOCS',
            priority: 'normal',
            descriptionKey: 'KANBAN_TEMPLATES.PROJECT.TASKS.WRITE_DOCS_DESC',
          },
          {
            titleKey: 'KANBAN_TEMPLATES.PROJECT.TASKS.TEAM_MEETING',
            priority: 'normal',
            descriptionKey: 'KANBAN_TEMPLATES.PROJECT.TASKS.TEAM_MEETING_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.PROJECT.STEPS.IN_PROGRESS',
        color: '#60a5fa',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.PROJECT.TASKS.DEV_CORE',
            priority: 'normal',
            descriptionKey: 'KANBAN_TEMPLATES.PROJECT.TASKS.DEV_CORE_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.PROJECT.STEPS.BLOCKED',
        color: '#ef4444',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.PROJECT.TASKS.API_KEYS',
            priority: 'urgent',
            descriptionKey: 'KANBAN_TEMPLATES.PROJECT.TASKS.API_KEYS_DESC',
          },
        ],
      },
      {
        nameKey: 'KANBAN_TEMPLATES.PROJECT.STEPS.DONE',
        color: '#34d399',
        tasks_attributes: [
          {
            titleKey: 'KANBAN_TEMPLATES.PROJECT.TASKS.DEPLOY_STAGING',
            priority: 'high',
            descriptionKey:
              'KANBAN_TEMPLATES.PROJECT.TASKS.DEPLOY_STAGING_DESC',
          },
        ],
      },
    ],
  },
];
