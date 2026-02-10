module EnsureCurrentAccountHelper
  private

  def current_account
    @current_account ||= ensure_current_account
    Current.account = @current_account
  end

  def ensure_current_account
    account = Account.find(params[:account_id])
    Rails.logger.info("[EnsureCurrentAccountHelper#ensure_current_account] account_id=#{account.id}, account_active=#{account.active?}")
    render_unauthorized('Account is suspended') and return unless account.active?

    Rails.logger.info("[EnsureCurrentAccountHelper#ensure_current_account] current_user=#{Current.user&.class&.name}, @resource=#{@resource&.class&.name}")
    if current_user
      Rails.logger.info("[EnsureCurrentAccountHelper#ensure_current_account] Checking account_accessible_for_user")
      account_accessible_for_user?(account)
    elsif @resource.is_a?(AgentBot)
      Rails.logger.info("[EnsureCurrentAccountHelper#ensure_current_account] Checking account_accessible_for_bot")
      account_accessible_for_bot?(account)
    else
      Rails.logger.info("[EnsureCurrentAccountHelper#ensure_current_account] No current_user or AgentBot, resource_type=#{@resource&.class&.name}")
    end
    account
  end

  def account_accessible_for_user?(account)
    @current_account_user = account.account_users.find_by(user_id: current_user.id)
    Current.account_user = @current_account_user
    render_unauthorized('You are not authorized to access this account') unless @current_account_user
  end

  def account_accessible_for_bot?(account)
    return if @resource.account_id == account.id
    return if @resource.agent_bot_inboxes.find_by(account_id: account.id)

    render_unauthorized('Bot is not authorized to access this account')
  end
end
