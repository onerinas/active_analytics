require "active_analytics/version"
require "active_analytics/engine"
require "active_analytics/redis"
require "browser"

module ActiveAnalytics
  mattr_accessor :base_controller_class, default: "ActionController::Base"

  def self.redis_url=(string)
    @redis_url = string
  end

  def self.redis_url
    @redis_url ||= ENV["ACTIVE_ANALYTICS_REDIS_URL"] || ENV["REDIS_URL"] || "redis://localhost"
  end

  def self.redis=(connection)
    @redis = connection
  end

  def self.redis
    @redis ||= Redis.new(url: redis_url)
  rescue ::Redis::CannotConnectError => e
    if Rails.env.test?
      raise e
    else
      Rails.logger.error("Redis connection failed: #{e.message}")
      nil
    end
  end

  def self.record_request(request)
    params = {
      site: request.host,
      page: request.path,
      date: Date.today,
    }
    if request.referrer.present?
      params[:referrer_host], params[:referrer_path] = ViewsPerDay.split_referrer(request.referrer)
    end

    # Extract UTM parameters from the request
    utm_params = extract_utm_parameters(request)
    params.merge!(utm_params)

    ViewsPerDay.append(params)

    browser = Browser.new(request.headers["User-Agent"])
    BrowsersPerDay.append(site: request.host, date: Date.today, name: browser.name, version: browser.version)
  rescue => ex
    if Rails.env.development? || Rails.env.test?
      raise ex
    else
      Rails.logger.error(ex.inspect)
      Rails.logger.error(ex.backtrace.join("\n"))
    end
  end

  SEPARATOR = "|"

  PAGE_QUEUE = "ActiveAnalytics::PageQueue"
  BROWSER_QUEUE = "ActiveAnalytics::BrowserQueue"

  OLD_PAGE_QUEUE = "ActiveAnalytics::OldPageQueue"
  OLD_BROWSER_QUEUE = "ActiveAnalytics::BrowserQueue"

  def self.queue_request(request)
    queue_request_page(request)
    queue_request_browser(request)
  end

  def self.queue_request_page(request)
    return unless redis # Skip if Redis is not available

    keys = [request.host, request.path]

    # Always add referrer fields (even if nil) to maintain consistent key structure
    if request.referrer.present?
      referrer_host, referrer_path = ViewsPerDay.split_referrer(request.referrer)
      keys.concat([referrer_host, referrer_path])
    else
      keys.concat([nil, nil])
    end

    # Add UTM parameters to the queue key, using nil for missing values
    utm_params = extract_utm_parameters(request)
    keys.concat([
      utm_params[:utm_source],
      utm_params[:utm_medium],
      utm_params[:utm_campaign],
      utm_params[:utm_term],
      utm_params[:utm_content]
    ])

    # Convert nils to a special placeholder (e.g., "~") for queue key
    safe_key = keys.map { |v| v.nil? ? "~" : v }.join(SEPARATOR).downcase
    redis.hincrby(PAGE_QUEUE, safe_key, 1)
  rescue ::Redis::CannotConnectError => e
    if Rails.env.test?
      raise e
    else
      Rails.logger.error("Redis connection failed: #{e.message}")
    end
  end

  def self.queue_request_browser(request)
    return unless redis # Skip if Redis is not available

    browser = Browser.new(request.headers["User-Agent"])
    keys = [request.host.downcase, browser.name, browser.version]
    redis.hincrby(BROWSER_QUEUE, keys.join(SEPARATOR), 1)
  rescue ::Redis::CannotConnectError => e
    if Rails.env.test?
      raise e
    else
      Rails.logger.error("Redis connection failed: #{e.message}")
    end
  end

  def self.flush_queue
    flush_page_queue
    flush_browser_queue
  end

  def self.flush_page_queue
    return unless redis && redis.exists?(PAGE_QUEUE)

    date = Date.today
    redis.rename(PAGE_QUEUE, OLD_PAGE_QUEUE)
    redis.hscan_each(OLD_PAGE_QUEUE) do |key, count|
      # Convert "~" placeholders back to nil
      site, page, referrer_host, referrer_path, utm_source, utm_medium, utm_campaign, utm_term, utm_content = key.split(SEPARATOR).map { |v| v == "~" ? nil : v }
      ViewsPerDay.append(
        date: date,
        site: site,
        page: page,
        referrer_host: referrer_host,
        referrer_path: referrer_path,
        utm_source: utm_source.presence,
        utm_medium: utm_medium.presence,
        utm_campaign: utm_campaign.presence,
        utm_term: utm_term.presence,
        utm_content: utm_content.presence,
        total: count.to_i
      )
    end
    redis.del(OLD_PAGE_QUEUE)
  rescue ::Redis::CannotConnectError => e
    if Rails.env.test?
      raise e
    else
      Rails.logger.error("Redis connection failed: #{e.message}")
    end
  end

  def self.flush_browser_queue
    return unless redis && redis.exists?(BROWSER_QUEUE)

    date = Date.today
    redis.rename(BROWSER_QUEUE, OLD_BROWSER_QUEUE)
    redis.hscan_each(OLD_BROWSER_QUEUE) do |key, count|
      site, name, version = key.split(SEPARATOR)
      BrowsersPerDay.append(date: date, site: site, name: name, version: version, total: count.to_i)
    end
    redis.del(OLD_BROWSER_QUEUE)
  rescue ::Redis::CannotConnectError => e
    if Rails.env.test?
      raise e
    else
      Rails.logger.error("Redis connection failed: #{e.message}")
    end
  end

  private

  def self.extract_utm_parameters(request)
    utm_params = {}

    # Extract UTM parameters from query string
    query_params = request.query_parameters || {}

    # Only set UTM parameters if they have a value
    utm_params[:utm_source] = query_params['utm_source'].presence
    utm_params[:utm_medium] = query_params['utm_medium'].presence
    utm_params[:utm_campaign] = query_params['utm_campaign'].presence
    utm_params[:utm_term] = query_params['utm_term'].presence
    utm_params[:utm_content] = query_params['utm_content'].presence

    # Convert empty strings to nil
    utm_params.transform_values! { |v| v == "" ? nil : v }

    utm_params
  end
end
