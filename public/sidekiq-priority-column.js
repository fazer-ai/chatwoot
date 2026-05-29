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

  // Sentinel used when a queue isn't in PRIORITY_ORDER (e.g. transient
  // gem queues like `sidekiq-alive-*`). Sorting these to the end of the
  // table mirrors how Sidekiq itself drains them: only after every
  // known-priority queue is empty.
  const UNKNOWN_PRIORITY = Number.MAX_SAFE_INTEGER;

  function injectColumn() {
    if (!isQueuesPage()) return;

    const table = document.querySelector('table.table');
    if (!table) return;
    if (table.dataset.priorityInjected === '1') return;
    table.dataset.priorityInjected = '1';

    // Header: prepend "Prioridade" as the first column.
    const headerRow = table.querySelector('thead tr');
    if (headerRow) {
      const th = document.createElement('th');
      th.textContent = 'Prioridade';
      th.style.textAlign = 'right';
      headerRow.insertBefore(th, headerRow.firstElementChild);
    }

    // Data rows: prepend the priority cell, then re-sort rows by priority
    // ascending. Each row's first cell (now after our insert: second cell)
    // has an anchor with the queue name.
    const tbody = table.querySelector('tbody');
    if (!tbody) return;

    const rows = Array.from(tbody.querySelectorAll('tr'));
    rows.forEach((row) => {
      const link = row.querySelector('td a');
      const queueName = link ? link.textContent.trim() : '';
      const priority = PRIORITY_BY_QUEUE[queueName];

      const td = document.createElement('td');
      td.textContent = priority != null ? String(priority) : '—';
      td.style.textAlign = 'right';
      row.insertBefore(td, row.firstElementChild);

      // Stash the sort key on the row so we can reorder without
      // re-parsing the cell text later.
      row.dataset.priority = priority != null ? String(priority) : String(UNKNOWN_PRIORITY);
    });

    rows
      .slice()
      .sort((a, b) => Number(a.dataset.priority) - Number(b.dataset.priority))
      .forEach((row) => tbody.appendChild(row));
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', injectColumn);
  } else {
    injectColumn();
  }
})();
