require "redis"

module ActiveAnalytics
  class Redis
    class << self
      def new(url: nil)
        url ||= ActiveAnalytics.redis_url
        ::Redis.new(url: url)
      end
    end
  end
end
