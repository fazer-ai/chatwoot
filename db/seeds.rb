# loading installation configs
GlobalConfig.clear_cache
ConfigLoader.new.process

## Seeds productions
if Rails.env.production?
  # Setup Onboarding flow
  Redis::Alfred.set(Redis::Alfred::CHATWOOT_INSTALLATION_ONBOARDING, true)
end

## Seeds for Local Development
unless Rails.env.production?

  # Enables creating additional accounts from dashboard
  installation_config = InstallationConfig.find_by(name: 'CREATE_NEW_ACCOUNT_FROM_DASHBOARD')
  installation_config.value = true
  installation_config.save!
  GlobalConfig.clear_cache

  seed_suffix = Time.current.strftime('%Y%m%d%H%M%S')

  account = Account.create!(
    name: "Acme Inc #{seed_suffix}"
  )

  secondary_account = Account.create!(
    name: "Acme Org #{seed_suffix}"
  )

  user = User.find_or_initialize_by(email: 'john@acme.inc') do |record|
    record.name = 'John'
  end
  user.assign_attributes(name: 'John', password: 'Password1!', type: 'SuperAdmin')
  user.skip_confirmation! if user.new_record?
  user.save!

  AccountUser.create!(
    account_id: account.id,
    user_id: user.id,
    role: :administrator
  )

  AccountUser.find_or_create_by!(
    account_id: secondary_account.id,
    user_id: user.id
  ) do |membership|
    membership.role = :administrator
  end

  web_widget = Channel::WebWidget.create!(account: account, website_url: "https://acme.inc/#{seed_suffix}")

  inbox = Inbox.create!(channel: web_widget, account: account, name: "Acme Support #{seed_suffix}")
  InboxMember.create!(user: user, inbox: inbox)

  contact_inbox = ContactInboxWithContactBuilder.new(
    source_id: user.id,
    inbox: inbox,
    hmac_verified: true,
    contact_attributes: { name: 'jane', email: 'jane@example.com', phone_number: '+2320000' }
  ).perform

  conversation = Conversation.create!(
    account: account,
    inbox: inbox,
    status: :open,
    assignee: user,
    contact: contact_inbox.contact,
    contact_inbox: contact_inbox,
    additional_attributes: {}
  )

  # sample email collect
  Seeders::MessageSeeder.create_sample_email_collect_message conversation

  Message.create!(content: 'Hello', account: account, inbox: inbox, conversation: conversation, sender: contact_inbox.contact,
                  message_type: :incoming)

  # sample location message
  #
  location_message = Message.new(content: 'location', account: account, inbox: inbox, sender: contact_inbox.contact, conversation: conversation,
                                 message_type: :incoming)
  location_message.attachments.new(
    account_id: account.id,
    file_type: 'location',
    coordinates_lat: 37.7893768,
    coordinates_long: -122.3895553,
    fallback_title: 'Bay Bridge, San Francisco, CA, USA'
  )
  location_message.save!

  # sample card
  Seeders::MessageSeeder.create_sample_cards_message conversation
  # input select
  Seeders::MessageSeeder.create_sample_input_select_message conversation
  # form
  Seeders::MessageSeeder.create_sample_form_message conversation
  # articles
  Seeders::MessageSeeder.create_sample_articles_message conversation
  # csat
  Seeders::MessageSeeder.create_sample_csat_collect_message conversation

  CannedResponse.create!(account: account, short_code: 'start', content: 'Hello welcome to chatwoot.')

  account.enable_features('kanban')

  agent_user = User.find_or_initialize_by(email: 'agent@acme.inc') do |record|
    record.name = 'Mia Agent'
    record.password = 'Password1!'
  end
  if agent_user.new_record?
    agent_user.skip_confirmation!
    agent_user.save!
  end

  AccountUser.create!(account: account, user: agent_user, role: :agent)

  kanban_board = account.kanban_boards.create!(
    name: 'Sample Sales Board',
    description: 'Demo pipeline used by seeds to exercise Kanban APIs',
    settings: { 'default_view' => 'kanban' }
  )

  step_definitions = [
    { name: 'New Lead', description: 'Inbound leads waiting for first touch', color: '#0ea5e9' },
    { name: 'Qualification', description: 'Active discovery', color: '#14b8a6' },
    { name: 'Proposal', description: 'Proposal sent to prospect', color: '#f59e0b' }
  ]

  steps = step_definitions.each_with_index.to_h do |attrs, index|
    step = kanban_board.steps.create!(attrs.merge(position: index))
    [attrs[:name], step]
  end

  kanban_board.board_inboxes.create!(inbox: inbox)
  kanban_board.board_agents.create!(agent: agent_user)

  demo_tasks = [
    {
      title: 'Follow up with Jane',
      description: 'Send intro email and schedule qualification call.',
      priority: 'high',
      board_step: steps['Qualification'],
      start_date: 1.day.ago,
      end_date: 2.days.from_now
    },
    {
      title: 'Share pricing proposal',
      description: 'Prepare proposal deck and share with contact prior to Friday.',
      priority: 'urgent',
      board_step: steps['Proposal'],
      start_date: Time.current,
      end_date: 5.days.from_now
    }
  ]

  demo_tasks.each do |attributes|
    task = kanban_board.tasks.create!(
      account: account,
      board_step: attributes[:board_step] || steps['New Lead'],
      creator: user,
      assigned_agent: agent_user,
      title: attributes[:title],
      description: attributes[:description],
      priority: attributes[:priority],
      start_date: attributes[:start_date],
      end_date: attributes[:end_date]
    )

    contact = contact_inbox.contact
    task.contacts << contact unless task.contacts.exists?(contact.id)
    task.conversations << conversation unless task.conversations.exists?(conversation.id)
  end
end
