class ApplicationController < ActionController::Base
  protect_from_forgery
  attr_accessor :current_user
  helper_method :current_user
  before_filter :set_foursquare_user

  def set_foursquare_user
    @current_user = get_current_user
    # make sure we always set the user's access token from the cookie, instead of db:
    @current_user.access_token = cookies.signed[:access_token] if cookies.signed[:access_token].present?
    @current_user
  end

  def api_version
    "20140825"
  end

  def not_found
    raise ActionController::RoutingError.new('Not Found')
  end

  rescue_from Foursquare2::APIError do |error|
    if error.message =~ /invalid_auth/
      redirect_to :controller => :session, :action => :logout
      return
    end
    logger.error "Foursquare2::APIError: #{error.message}"
    logger.error error.backtrace.join("\n")
    #logger.error "Auth token: #{@current_user.access_token}"
    redirect_to :controller => :session, :action => :error
    return
  end

  rescue_from ActionController::RoutingError do |error|
    logger.error "Could not find: #{error.message}"
    redirect_to :controller=>:session, :action=>:error
  end

  rescue_from Faraday::Error::ParsingError do |error|
    logger.error "Parsing Error from Faraday: #{error}"
    if error.message =~ /backend read error/
      logger.error "Backend read error!"
    end
    if !request.path.include?('session/error')
      redirect_to :controller => :session, :action => :error
      return
    end
  end

  def foursquare_userless
    @foursquare ||= Foursquare2::Client.new(:client_id => Settings.app_id, :client_secret => Settings.app_secret, :connection_middleware => [Faraday::Response::Logger, FaradayMiddleware::Instrumentation], :api_version => api_version)
  end

  private
    def require_user
      if cookies.signed[:access_token] == nil
        redirect_to :controller => :session, :action => :new
        return false
      end
      @current_user = current_user
      if @current_user.nil?
        redirect_to :controller => :session, :action => :new
      elsif !@current_user.allowed?
        redirect_to :controller => :session, :action => :not_allowed unless @current_user.allowed?
      end
    end

    def get_current_user
      return nil if cookies.signed[:access_token].blank?

      begin
        foursquare = Foursquare2::Client.new(:oauth_token => cookies.signed[:access_token], :connection_middleware => [Faraday::Response::Logger, FaradayMiddleware::Instrumentation], :api_version => api_version)
        @current_user ||= User.find_by_uid(foursquare.user('self').id)
        # TODO: remove when removing user.token
        # ensure existing users that are logged in have the user's database stored token set in the cookie:
        if @current_user.has_attribute?(:token) && @current_user.token.present? && !cookies.signed[:access_token].present?
          cookies.permanent.signed[:access_token] = @current_user.token
        end
        # set the user access token (so it uses that instead of the database stored):
        @current_user.access_token = cookies.signed[:access_token]
      rescue Foursquare2::APIError
        cookies.signed[:access_token] = nil
        redirect_to :controller => :session, :action => :new
      end

      @current_user
    end

    def flag_counts
      @flagcount =  @current_user.flags.where('status IN (?)', ['new','queued']).count()
    end
end
