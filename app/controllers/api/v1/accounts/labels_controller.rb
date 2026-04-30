class Api::V1::Accounts::LabelsController < Api::V1::Accounts::BaseController
  PROTECTED_LABEL_TITLES = %w[agente-off].freeze
  PROTECTED_LABEL_PREFIXES = %w[kb-].freeze

  before_action :current_account
  before_action :fetch_label, except: [:index, :create]
  before_action :check_authorization
  before_action :prevent_protected_label_modification, only: [:update, :destroy]

  def index
    @labels = policy_scope(Current.account.labels)
  end

  def show; end

  def create
    @label = Current.account.labels.create!(permitted_params)
  end

  def update
    @label.update!(permitted_params)
  end

  def destroy
    @label.destroy!
    head :ok
  end

  private

  def fetch_label
    @label = Current.account.labels.find(params[:id])
  end

  def permitted_params
    params.require(:label).permit(:title, :description, :color, :show_on_sidebar)
  end

  def prevent_protected_label_modification
    return unless Current.account_user&.manager?
    return unless protected_label?(@label)

    raise Pundit::NotAuthorizedError
  end

  def protected_label?(label)
    title = label&.title.to_s
    return false if title.blank?

    PROTECTED_LABEL_TITLES.include?(title) || PROTECTED_LABEL_PREFIXES.any? { |prefix| title.start_with?(prefix) }
  end
end
