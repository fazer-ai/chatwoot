# PRD: Atalhos de Tempo para Mensagens Agendadas

## Objetivo

Melhorar a experiência do usuário ao criar novos agendamentos de mensagens, tornando o processo mais rápido com atalhos de tempo pré-definidos. A forma atual de agendar mensagens (seleção manual de data e hora) será mantida como opção "Personalizado".

## Contexto

Atualmente, o modal de agendamento de mensagens (`ScheduledMessageModal.vue`) utiliza um date picker (`vue-datepicker-next`) para seleção de data e hora. O usuário precisa navegar pelo calendário e selecionar manualmente hora e minuto, o que é lento para os casos de uso mais comuns.

## Funcionalidade

### Visão Geral

Substituir a seção do date picker por dois seletores de chips (botões):
1. **Seletor de Dia** — atalhos de dia pré-definidos
2. **Seletor de Turno** — atalhos de horário pré-definidos

Quando o usuário seleciona um dia + um turno, o sistema calcula automaticamente a data/hora resultante. A opção "Personalizado" exibe o date picker existente para seleção manual.

### Atalhos de Dia

| # | Opção | Regra | Exemplo |
|---|---|---|---|
| 1 | Hoje | Data atual | Hoje 13/03 |
| 2 | Amanhã | Data atual + 1 dia | Amanhã 14/03 |
| 3 | Este final de semana | Próximo sábado (se hoje é sábado, retorna hoje; se domingo, retorna próximo sábado) | Este final de semana 15/03 |
| 4 | Próxima semana | Próxima segunda-feira | Próxima semana 17/03 |
| 5 | Próximo final de semana | Sábado seguinte (sempre ≥7 dias após "Este final de semana") | Próximo final de semana 22/03 |
| 6 | Próximo mês | Primeiro dia do próximo mês | Próximo mês 01/04 |
| 7 | Personalizado | Exibe o date picker existente | — |

- Cada opção de dia exibe a data correspondente (dd/MM) em cor secundária (`text-n-slate-11`)
- "Personalizado" não exibe data

### Atalhos de Turno

| # | Opção | Horário |
|---|---|---|
| 1 | Manhã | 8:00 |
| 2 | Tarde | 13:00 |
| 3 | Noite | 18:00 |

- Os atalhos de turno **só aparecem** quando um atalho de dia é selecionado (exceto "Personalizado")
- Cada opção de turno exibe o horário em cor secundária (`text-n-slate-11`)

### Comportamento

1. Usuário clica em um chip de dia → o seletor de turno aparece
2. O primeiro turno válido (não passado) é auto-selecionado
3. Usuário pode trocar o turno clicando em outro chip
4. A data/hora resultante é emitida via `v-model` para o modal pai
5. Ao selecionar "Personalizado", os chips de turno somem e o date picker aparece
6. O modal pai (`ScheduledMessageModal.vue`) continua usando `scheduledDateTime` sem alteração no fluxo de dados downstream (`scheduledAt`, `buildPayload`, `validatePayload`, `submit`)

## Casos de Borda

| Caso | Comportamento |
|---|---|
| "Hoje" + turno já passado (ex: "Manhã" às 14h) | O chip do turno fica desabilitado (opacity reduzida, `cursor-not-allowed`) |
| Todos os turnos passados para "Hoje" | Nenhum turno auto-selecionado; usuário deve escolher outro dia ou "Personalizado" |
| Hoje é sábado → "Este final de semana" | Retorna hoje (sábado) |
| Hoje é domingo → "Este final de semana" | Retorna próximo sábado |
| Edição de mensagem agendada existente | Chips iniciam sem seleção; data existente é mantida até o usuário interagir |
| Modal reaberto (reset) | `modelValue = null` limpa os chips de seleção |
| "Salvar como rascunho" (sem data) | Funciona normalmente, sem necessidade de selecionar dia/turno |

## Arquitetura Técnica

### Arquivos a Criar

| Arquivo | Descrição |
|---|---|
| `app/javascript/dashboard/helper/scheduleDateShortcutHelpers.js` | Funções puras de cálculo de data (constantes, `getShortcutDate`, `applyTimePeriod`, `isTimePeriodPast`, `formatShortDate`, `getDayShortcutOptions`) |
| `app/javascript/dashboard/routes/dashboard/conversation/scheduledMessages/ScheduleDateShortcuts.vue` | Componente Vue com `<script setup>`, chips de dia + turno + date picker condicional |

### Arquivos a Modificar

| Arquivo | Mudança |
|---|---|
| `app/javascript/dashboard/routes/dashboard/conversation/scheduledMessages/ScheduledMessageModal.vue` | Substituir seção do DatePicker por `<ScheduleDateShortcuts v-model="scheduledDateTime" />`. Remover imports e funções relacionadas ao DatePicker que migram para o novo componente |
| `app/javascript/dashboard/i18n/locale/en/conversation.json` | Adicionar chaves `SCHEDULED_MESSAGES.MODAL.SHORTCUTS.*` |
| `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json` | Adicionar traduções pt-BR correspondentes |

### Fluxo de Dados

```
ScheduledMessageModal.vue
│
│   scheduledDateTime (ref<Date|null>)   ← já existe, sem alteração
│           │
│   ┌───────▼────────────────────────┐
│   │  ScheduleDateShortcuts.vue     │
│   │   v-model = scheduledDateTime  │
│   │                                │
│   │  ┌─ Chips de Dia ───────────┐  │
│   │  │ Hoje | Amanhã | ...      │  │
│   │  │ ... | Personalizado      │  │
│   │  └──────────────────────────┘  │
│   │                                │
│   │  ┌─ Chips de Turno ────────┐   │  (visível quando dia ≠ personalizado)
│   │  │ Manhã | Tarde | Noite   │   │
│   │  └─────────────────────────┘   │
│   │                                │
│   │  ┌─ DatePicker ────────────┐   │  (visível quando dia = personalizado)
│   │  │ vue-datepicker-next     │   │
│   │  └─────────────────────────┘   │
│   └────────────────────────────────┘
│
│   scheduledAt (computed) → buildPayload() → submit()   ← sem alteração
```

### Constantes e Helpers

```javascript
// Opções de dia
SCHEDULE_DAY_OPTIONS = {
  TODAY, TOMORROW, THIS_WEEKEND, NEXT_WEEK,
  NEXT_WEEKEND, NEXT_MONTH, CUSTOM
}

// Opções de turno
SCHEDULE_TIME_PERIODS = { MORNING, AFTERNOON, EVENING }
TIME_PERIOD_HOURS = { morning: 8, afternoon: 13, evening: 18 }

// Funções
getShortcutDate(dayKey, now?)      → Date (meia-noite do dia alvo)
applyTimePeriod(date, timePeriod)  → Date (com hora aplicada)
isTimePeriodPast(date, timePeriod, now?) → boolean
formatShortDate(date)              → string "dd/MM"
getDayShortcutOptions(now?)        → Array<{key, labelI18nKey, date, formattedDate}>
```

### Chaves i18n

```json
// en/conversation.json → SCHEDULED_MESSAGES.MODAL.SHORTCUTS
{
  "DAYS_LABEL": "Day",
  "TIMES_LABEL": "Time",
  "DAYS": {
    "TODAY": "Today",
    "TOMORROW": "Tomorrow",
    "THIS_WEEKEND": "This weekend",
    "NEXT_WEEK": "Next week",
    "NEXT_WEEKEND": "Next weekend",
    "NEXT_MONTH": "Next month",
    "CUSTOM": "Custom"
  },
  "TIMES": {
    "MORNING": "Morning",
    "AFTERNOON": "Afternoon",
    "EVENING": "Evening"
  }
}

// pt_BR/conversation.json → SCHEDULED_MESSAGES.MODAL.SHORTCUTS
{
  "DAYS_LABEL": "Dia",
  "TIMES_LABEL": "Turno",
  "DAYS": {
    "TODAY": "Hoje",
    "TOMORROW": "Amanhã",
    "THIS_WEEKEND": "Este final de semana",
    "NEXT_WEEK": "Próxima semana",
    "NEXT_WEEKEND": "Próximo final de semana",
    "NEXT_MONTH": "Próximo mês",
    "CUSTOM": "Personalizado"
  },
  "TIMES": {
    "MORNING": "Manhã",
    "AFTERNOON": "Tarde",
    "EVENING": "Noite"
  }
}
```

### Estilo dos Chips (Tailwind)

| Estado | Classes |
|---|---|
| Não selecionado | `bg-n-alpha-1 dark:bg-n-solid-1 text-n-slate-12 hover:bg-n-alpha-2 dark:hover:bg-n-solid-3` |
| Selecionado | `bg-n-brand/10 text-n-blue-11 font-medium` |
| Desabilitado | `opacity-40 cursor-not-allowed bg-n-alpha-1 dark:bg-n-solid-1 text-n-slate-10` |
| Base | `inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm border-0 transition-colors duration-150` |

## Padrões Seguidos

- `<script setup>` + Composition API (padrão `components-next/`)
- Tailwind-only, sem CSS customizado ou scoped
- Tokens de design `n-*` (Radix colors)
- `date-fns` para cálculos de data (já usado no projeto)
- Componente emite via `v-model` (`update:modelValue`) — sem mudança no Vuex
- Inspirado no padrão de snooze shortcuts (`snoozeHelpers.js`) e `CalendarDateRange.vue`

## Branch

- **Nome**: `Cayo-Oliveira/CU-86aezwnp2/Atalhos-Amanha-de-manha-etc`
- **Base**: `feat/find-scheduled-message`

## Impacto

- **Backend**: Nenhuma alteração necessária. O backend recebe `scheduled_at` como ISO string — o cálculo é inteiramente no frontend
- **Vuex**: Nenhuma alteração. O `scheduledDateTime` ref no modal é o ponto de integração
- **Enterprise**: Sem impacto. Feature não tem overrides em `enterprise/`
- **Testes**: Funções helper são puras e testáveis com `now` injetável
