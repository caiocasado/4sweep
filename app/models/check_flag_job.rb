class CheckFlagJob < Struct.new(:flag, :token)

  def perform
    flag.access_token = token
    flag.resolved?
  end

  def error(job, exception)
    @exception = exception
  end

  def reschedule_at(time_now, attempts)
    if (@exception.is_a?(Foursquare2::APIError) && @exception.type == 'rate_limit_exceeded') # Rate limit hit

      # Photo and Tip flags have their own endpoint with their own rate limit
      if ["PhotoFlag", "TipFlag"].include? flag.type
        flags_of_type = flag.user.flags.where(:status => ["queued", "submitted"]).where(:type => flag.type).count
        rate_limit = 500
      else
        flags_of_type = flag.user.flags.where(:status => ["queued", "submitted"]).where("type NOT IN (?)", ["PhotoFlag", "TipFlag"]).count
        rate_limit = 5000
      end
      # If this fails due to rate_limit_exceeded, figure out how long it will take to process all flags
      # of this type and randomly assign a time in that window. It's hacky and brittle, but better than
      # every job retrying at the same time.
      # TODO: make this reschedule all likely to fail flags, not just this one
      return time_now + (60*60 * ((flags_of_type / rate_limit) + 1) * rand).to_i
    else
      return time_now + (attempts ** 4) + 5 #default exponential backoff
    end
  end

end
