// Injects a "Prioridade" column into the Sidekiq Web /queues table so Ops
// can see at a glance which queue runs at which priority level. Loaded by
// the Sidekiq Web UI via `Sidekiq::Web.custom_javascript` (wired in
// `config/initializers/sidekiq.rb`).
//
// IMPORTANT: the list below MUST stay in sync with `config/sidekiq.yml`.
// A spec at `spec/configs/sidekiq_priority_column_spec.rb` enforces this
// by parsing both files and asserting the order is identical — drift will
// fail CI.

(function () {
  // Order matches `:queues:` in `config/sidekiq.yml`. Index + 1 is the
  // priority level the operator sees (Sidekiq strict ordering means
  // queue #1 always wins over #2, and so on).
  const PRIORITY_ORDER = [
    'critical',
    'high',
    'medium',
    'default',
    'mailers',
    'action_mailbox_routing',
    'whatsapp_messages',
    'low',
    'whatsapp_history',
    'scheduled_jobs',
    'deferred',
    'purgable',
    'housekeeping',
    'async_database_migration',
    'bulk_reindex_low',
    'active_storage_analysis',
    'active_storage_purge',
    'action_mailbox_incineration',
  ];

  const PRIORITY_BY_QUEUE = Object.fromEntries(
    PRIORITY_ORDER.map((name, idx) => [name, idx + 1])
  );

  function isQueuesPage() {
    // Path is `/monitoring/sidekiq/queues` (or any other mount point + /queues).
    return /\/queues\/?$/.test(window.location.pathname);
  }

  function injectColumn() {
    if (!isQueuesPage()) return;

    const table = document.querySelector('table.table');
    if (!table) return;
    if (table.dataset.priorityInjected === '1') return;
    table.dataset.priorityInjected = '1';

    // Header: insert "Prioridade" right before the last column (the
    // actions column, which holds the "Apagar" button).
    const headerRow = table.querySelector('thead tr');
    if (headerRow) {
      const th = document.createElement('th');
      th.textContent = 'Prioridade';
      th.style.textAlign = 'right';
      headerRow.insertBefore(th, headerRow.lastElementChild);
    }

    // Data rows: each row's first cell has an anchor with the queue name.
    // Transient queues registered by gems (e.g. `sidekiq-alive-*`) won't
    // be in PRIORITY_ORDER — render an em dash for those.
    table.querySelectorAll('tbody tr').forEach((row) => {
      const link = row.querySelector('td a');
      if (!link) return;
      const queueName = link.textContent.trim();
      const priority = PRIORITY_BY_QUEUE[queueName];
      const td = document.createElement('td');
      td.textContent = priority != null ? String(priority) : '—';
      td.style.textAlign = 'right';
      row.insertBefore(td, row.lastElementChild);
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', injectColumn);
  } else {
    injectColumn();
  }
})();
