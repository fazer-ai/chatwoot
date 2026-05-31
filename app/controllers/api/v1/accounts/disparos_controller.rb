class Api::V1::Accounts::DisparosController < Api::V1::Accounts::BaseController
  # Beta 0 reads are bounded: a single disparo can fan out to a large audience,
  # so the targets listing is capped to keep the response (and the query) small.
  TARGETS_PER_PAGE = 50
  # The index listing is likewise capped so an account with many drafts cannot
  # dump an unbounded payload; clients page through with ?page=N.
  DISPAROS_PER_PAGE = 25

  before_action :ensure_beta0_visible
  before_action :fetch_disparo, only: [:show, :dry_run, :shadow_run, :targets]

  # Read-only listing of the current account's disparos. Ordered by created_at
  # then id for a stable, deterministic order across pages, and capped
  # (DISPAROS_PER_PAGE) so the response stays bounded.
  def index
    authorize Disparo
    @disparos = account_disparos.includes(:disparo_inboxes).order(created_at: :desc, id: :desc).page(params[:page]).per(DISPAROS_PER_PAGE)
  end

  def show
    authorize @disparo
  end

  def create
    authorize Disparo
    invalid_reason = invalid_attributes_reason
    return render_could_not_create_error(invalid_reason) if invalid_reason

    inboxes = account_inboxes_for(params.dig(:disparo, :inbox_ids))
    # A disparo with no inbox can never run: the audience filter requires at least
    # one inbox (AudienceResolver raises invalid_audience_filter on blank inbox_ids)
    # and there is no update action to add one later. Reject the empty set BEFORE
    # persisting so we never leave a permanently un-runnable draft. The empty check
    # precedes cloud_inbox? because `[].all?` is vacuously true and would mask this.
    return render_could_not_create_error('invalid_audience_filter') if inboxes.empty?
    return render_could_not_create_error('unsupported_inbox_provider') unless inboxes.all? { |inbox| cloud_inbox?(inbox) }
    # GAP A: the submitted template_category must equal the REAL category of the
    # approved template in EVERY selected inbox. Needs the resolved inboxes, so it
    # runs after the cloud guard (not in invalid_attributes_reason, which has none).
    return render_could_not_create_error('template_category_mismatch') unless template_category_matches?(inboxes)

    @disparo = build_disparo(inboxes)
    render :show, status: :created
  end

  def dry_run
    authorize @disparo
    @summary = Disparos::DryRunService.new(now: Time.current).perform(@disparo)
    render :dry_run
  rescue CustomExceptions::Disparos::InvalidDryRun => e
    render_could_not_create_error(e.message)
  end

  # Persists the shadow target set (read-only, no real send). The run is wrapped
  # in a row lock on the disparo so concurrent shadow_run requests on the SAME
  # disparo serialize (SELECT ... FOR UPDATE) — this closes the
  # find_or_initialize_by -> save! race the service deferred, since the unique
  # index (disparo_id, conversation_id, contact_id) would otherwise raise on a
  # parallel insert of the same target. The rescue stays OUTSIDE with_lock so a
  # pre-write validation failure rolls the (empty) transaction back cleanly.
  def shadow_run
    authorize @disparo
    # GAP B: the shadow run must reference the dry-run snapshot the operator
    # approved. A missing/blank snapshot_id is a 422 before any work; the service
    # then validates the snapshot's ownership, TTL and config fingerprint.
    return render_could_not_create_error('invalid_shadow_run') if params[:snapshot_id].blank?

    @summary = @disparo.with_lock do
      Disparos::ShadowRunService.new(now: Time.current, snapshot_id: params[:snapshot_id]).perform(@disparo)
    end
    render :shadow_run
  rescue CustomExceptions::Disparos::InvalidShadowRun => e
    render_could_not_create_error(e.message)
  end

  # Read-only listing of the persisted shadow targets, account-scoped through
  # @disparo. Ordered by id for determinism and capped (TARGETS_PER_PAGE) so a
  # large fan-out cannot dump an unbounded payload.
  def targets
    authorize @disparo
    @targets = @disparo.disparo_targets.order(:id).page(params[:page]).per(TARGETS_PER_PAGE)
    render :targets
  end

  private

  # Beta 0 "Disparador Cloud Shadow" is hidden behind an installation config flag.
  # When the flag is off the whole API surface must be invisible (404, never 403)
  # so its existence is not leaked. This is independent of BlockedSendGuard.
  def ensure_beta0_visible
    return if beta0_visible?

    head :not_found
  end

  def beta0_visible?
    ActiveModel::Type::Boolean.new.cast(GlobalConfigService.load('DISPARADOR_BETA0_VISIBLE', false))
  end

  def fetch_disparo
    @disparo = account_disparos.find(params[:id])
  end

  def account_disparos
    Disparo.where(account: Current.account)
  end

  # Boundary validation of the create attributes, returning the first failing reason
  # (or nil). A blank template_name would persist a dead draft (it can never be
  # dry-run/shadow-run and there is no update action to set one later), so it is
  # rejected here. The enum guards keep malformed input a 422 instead of a 500.
  def invalid_attributes_reason
    return 'invalid_template' if params.dig(:disparo, :template_name).blank?
    return 'invalid_template_category' unless valid_template_category?
    return 'invalid_conversation_status' unless valid_conversation_status?

    nil
  end

  # The Rails enum raises ArgumentError on an unknown value, which would surface as
  # a 500. Malformed client input on a public write endpoint must be a 4xx, so an
  # out-of-range template_category is rejected at the boundary (422). A blank/absent
  # value is allowed — the column defaults to utility.
  def valid_template_category?
    category = params.dig(:disparo, :template_category)
    category.blank? || Disparo.template_categories.key?(category)
  end

  # Same boundary guard as valid_template_category?: an out-of-range enum value would
  # raise ArgumentError (500) on assignment, so it is rejected as a 422 here. Blank is
  # allowed — the column defaults to open.
  def valid_conversation_status?
    status = params.dig(:disparo, :conversation_status)
    status.blank? || Disparo.conversation_statuses.key?(status)
  end

  # GAP A real-category guard: the EFFECTIVE submitted category (an omitted value
  # defaults to the column default — utility, matching the persisted disparo) must
  # equal the resolved category of `template_name` in EVERY selected inbox's
  # channel. A nil resolution (template not found / not approved / no category) in
  # ANY inbox is a mismatch, so a client can neither dispatch an unapproved
  # template nor bypass the marketing cooldown by omitting the category. The
  # enum-range guard already ran (valid_template_category?), so submitted is a
  # known enum key or blank here.
  #
  # exact: true — the operator's submitted template_name must match a synced
  # approved template EXACTLY (case-sensitive). A mis-cased name resolves to nil
  # → mismatch → 422, so it is never persisted; the canonical name then keeps the
  # engine's exact approval allowlist + BulkMarker dedup key aligned end-to-end.
  def template_category_matches?(inboxes)
    submitted = params.dig(:disparo, :template_category).presence || 'utility'
    template_name = params.dig(:disparo, :template_name)

    inboxes.all? do |inbox|
      Disparos::TemplateCategory.for_channel(inbox.channel, template_name, exact: true) == submitted
    end
  end

  def build_disparo(inboxes)
    Disparo.transaction do
      disparo = Disparo.create!(disparo_params.merge(account: Current.account, created_by: Current.user))
      inboxes.each { |inbox| disparo.disparo_inboxes.create!(inbox: inbox) }
      disparo
    end
  end

  # Only inboxes belonging to the current account may be linked. Any foreign or
  # unknown id is rejected at the boundary so a client cannot wire a disparo to
  # another account's inbox.
  def account_inboxes_for(inbox_ids)
    ids = Array(inbox_ids).map(&:to_i).uniq
    return [] if ids.empty?

    inboxes = Current.account.inboxes.where(id: ids)
    raise ActiveRecord::RecordNotFound, 'Inbox could not be found' unless inboxes.size == ids.size

    inboxes
  end

  # Beta 0 is exclusive_cloud: only WhatsApp Cloud inboxes may back a disparo. A
  # non-Cloud inbox (other WhatsApp providers, web-widget, email, ...) must be
  # rejected at creation so a draft cannot be mislabeled cloud. The && short-circuits
  # so non-WhatsApp inboxes never call channel.provider. Mirrors the downstream
  # EligibilityEngine unsupported_inbox_provider skip (defense in depth).
  def cloud_inbox?(inbox)
    inbox.whatsapp? && inbox.channel&.provider == 'whatsapp_cloud'
  end

  def disparo_params
    params.require(:disparo).permit(:name, :description, :template_name, :template_category, :conversation_status,
                                    audience_filter: [kanban_steps: [], label: []])
  end
end
