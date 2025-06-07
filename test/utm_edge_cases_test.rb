require "test_helper"

class UtmEdgeCasesTest < ActiveSupport::TestCase
  Request = Struct.new(:host, :path, :referrer, :headers, :query_parameters)

  def setup
    ActiveAnalytics::ViewsPerDay.delete_all
  end

  def test_handles_nil_query_parameters
    req = Request.new("site.test", "/page", nil, sample_headers, nil)

    assert_nothing_raised do
      ActiveAnalytics.record_request(req)
    end

    record = ActiveAnalytics::ViewsPerDay.last
    assert_nil record.utm_source
    assert_nil record.utm_medium
    assert_nil record.utm_campaign
  end

  def test_handles_empty_query_parameters
    req = Request.new("site.test", "/page", nil, sample_headers, {})

    assert_nothing_raised do
      ActiveAnalytics.record_request(req)
    end

    record = ActiveAnalytics::ViewsPerDay.last
    assert_nil record.utm_source
  end

  def test_handles_utm_parameters_with_special_characters
    query_params = {
      'utm_source' => 'google ads',
      'utm_medium' => 'cpc/display',
      'utm_campaign' => 'summer-sale_2024',
      'utm_term' => 'widgets & gadgets',
      'utm_content' => 'ad#1'
    }

    req = Request.new("site.test", "/page", nil, sample_headers, query_params)

    assert_nothing_raised do
      ActiveAnalytics.record_request(req)
    end

    record = ActiveAnalytics::ViewsPerDay.last
    assert_equal 'google ads', record.utm_source
    assert_equal 'cpc/display', record.utm_medium
    assert_equal 'summer-sale_2024', record.utm_campaign
    assert_equal 'widgets & gadgets', record.utm_term
    assert_equal 'ad#1', record.utm_content
  end

  def test_handles_very_long_utm_values
    long_value = 'a' * 1000  # Very long string

    query_params = {
      'utm_source' => long_value,
      'utm_campaign' => long_value
    }

    req = Request.new("site.test", "/page", nil, sample_headers, query_params)

    assert_nothing_raised do
      ActiveAnalytics.record_request(req)
    end

    record = ActiveAnalytics::ViewsPerDay.last
    assert_equal long_value, record.utm_source
    assert_equal long_value, record.utm_campaign
  end

  def test_handles_utm_parameters_with_unicode
    query_params = {
      'utm_source' => 'пуеуеуы',  # Cyrillic
      'utm_campaign' => '夏のセール',  # Japanese
      'utm_content' => 'café-médias'  # Accented characters
    }

    req = Request.new("site.test", "/page", nil, sample_headers, query_params)

    assert_nothing_raised do
      ActiveAnalytics.record_request(req)
    end

    record = ActiveAnalytics::ViewsPerDay.last
    assert_equal 'пуеуеуы', record.utm_source
    assert_equal '夏のセール', record.utm_campaign
    assert_equal 'café-médias', record.utm_content
  end

  def test_handles_case_sensitivity_in_utm_values
    # UTM values should be preserved as-is (case sensitive)
    req1 = Request.new("site.test", "/page", nil, sample_headers, {'utm_source' => 'Google'})
    req2 = Request.new("site.test", "/page", nil, sample_headers, {'utm_source' => 'google'})

    ActiveAnalytics.record_request(req1)
    ActiveAnalytics.record_request(req2)

    # Should create separate records
    assert_equal 2, ActiveAnalytics::ViewsPerDay.count

    sources = ActiveAnalytics::ViewsPerDay.group_by_utm_source
    assert_equal 2, sources.length
    assert sources.any? { |s| s.value == 'Google' }
    assert sources.any? { |s| s.value == 'google' }
  end

  def test_handles_malformed_queue_data_gracefully
    # Test with corrupted queue key that has wrong number of segments
    ActiveAnalytics.redis.hset(ActiveAnalytics::PAGE_QUEUE, "malformed|key", "1")

    assert_nothing_raised do
      ActiveAnalytics.flush_queue
    end

    # Should not crash, might create record with nil values
    # The important thing is it doesn't raise an exception
  end

  def test_handles_queue_data_with_empty_segments
    # Test queue key with empty segments (double separators)
    key = "site.test|/page|||utm_source||utm_campaign||"
    ActiveAnalytics.redis.hset(ActiveAnalytics::PAGE_QUEUE, key, "5")

    assert_nothing_raised do
      ActiveAnalytics.flush_queue
    end

    record = ActiveAnalytics::ViewsPerDay.last
    assert_equal "site.test", record.site
    assert_equal "/page", record.page
    assert_nil record.utm_source
    assert_nil record.utm_campaign
  end

  def test_utm_grouping_with_mixed_case_and_nil_values
    # Create records with mixed case and nil values
    ActiveAnalytics::ViewsPerDay.create!(
      site: "site.test", page: "/page1", date: Date.today, total: 10,
      utm_source: "Google", utm_campaign: "Summer"
    )

    ActiveAnalytics::ViewsPerDay.create!(
      site: "site.test", page: "/page2", date: Date.today, total: 15,
      utm_source: "google", utm_campaign: "summer"
    )

    ActiveAnalytics::ViewsPerDay.create!(
      site: "site.test", page: "/page3", date: Date.today, total: 5,
      utm_source: nil, utm_campaign: nil
    )

    sources = ActiveAnalytics::ViewsPerDay.group_by_utm_source
    campaigns = ActiveAnalytics::ViewsPerDay.group_by_utm_campaign

    # Should have 2 distinct sources (case sensitive)
    assert_equal 2, sources.length
    assert sources.any? { |s| s.value == "Google" && s.total == 10 }
    assert sources.any? { |s| s.value == "google" && s.total == 15 }

    # Should have 2 distinct campaigns (case sensitive)
    assert_equal 2, campaigns.length
    assert campaigns.any? { |c| c.value == "Summer" && c.total == 10 }
    assert campaigns.any? { |c| c.value == "summer" && c.total == 15 }
  end

  def test_utm_filtering_with_sql_injection_attempts
    # Test that UTM parameters are properly sanitized
    malicious_utm = "'; DROP TABLE active_analytics_views_per_days; --"

    query_params = {
      'utm_source' => malicious_utm,
      'utm_campaign' => "normal_campaign"
    }

    req = Request.new("site.test", "/page", nil, sample_headers, query_params)

    assert_nothing_raised do
      ActiveAnalytics.record_request(req)
    end

    # Table should still exist
    assert ActiveAnalytics::ViewsPerDay.table_exists?

    # Data should be stored as-is (escaped)
    record = ActiveAnalytics::ViewsPerDay.last
    assert_equal malicious_utm, record.utm_source
    assert_equal "normal_campaign", record.utm_campaign
  end

  def test_utm_overview_stats_with_no_data
    # Test stats calculation with empty database
    stats = ActiveAnalytics::ViewsPerDay.utm_overview_stats

    assert_equal 0, stats[:total_views]
    assert_equal 0, stats[:utm_views]
    assert_equal 0, stats[:utm_percentage]
    assert_equal 0, stats[:unique_campaigns]
    assert_equal 0, stats[:unique_sources]
    assert_nil stats[:top_landing_page]
  end

  def test_utm_overview_stats_with_no_utm_data
    # Test stats with traffic but no UTM data
    ActiveAnalytics::ViewsPerDay.create!(
      site: "site.test", page: "/page", date: Date.today, total: 100
    )

    stats = ActiveAnalytics::ViewsPerDay.utm_overview_stats

    assert_equal 100, stats[:total_views]
    assert_equal 0, stats[:utm_views]
    assert_equal 0.0, stats[:utm_percentage]
    assert_equal 0, stats[:unique_campaigns]
    assert_equal 0, stats[:unique_sources]
    assert_nil stats[:top_landing_page]
  end

  def test_campaign_performance_with_null_values
    # Test campaign performance analysis with some null source/medium values
    ActiveAnalytics::ViewsPerDay.create!(
      site: "site.test", page: "/page1", date: Date.today, total: 50,
      utm_campaign: "test_campaign", utm_source: "google", utm_medium: "cpc"
    )

    ActiveAnalytics::ViewsPerDay.create!(
      site: "site.test", page: "/page2", date: Date.today, total: 30,
      utm_campaign: "test_campaign", utm_source: nil, utm_medium: nil
    )

    performance = ActiveAnalytics::ViewsPerDay.campaign_performance_analysis

    assert_equal 2, performance.length

    google_campaign = performance.find { |p| p.source == "google" }
    nil_campaign = performance.find { |p| p.source.nil? }

    assert_equal 50, google_campaign.total
    assert_equal "google / cpc", google_campaign.source_medium

    assert_equal 30, nil_campaign.total
    assert_equal "Direct", nil_campaign.source_medium  # Should handle nil gracefully
  end

  def test_percentage_calculations_avoid_division_by_zero
    # Test that percentage calculations don't crash on zero totals
    data = ActiveAnalytics::ViewsPerDay::UtmData.new("test", 10, 0)

    assert_equal 0, data.percentage
    assert_equal "0%", data.percentage_display

    # Test with nil total_sum
    data_nil = ActiveAnalytics::ViewsPerDay::UtmData.new("test", 10, nil)
    assert_equal 0, data_nil.percentage
  end

  def test_redis_connection_failure_handling
    # Mock Redis failure during queue operations
    original_redis = ActiveAnalytics.redis

    # Mock a failing Redis connection
    failing_redis = Object.new
    def failing_redis.hincrby(*args)
      raise Redis::CannotConnectError, "Connection refused"
    end

    ActiveAnalytics.redis = failing_redis

    req = Request.new("site.test", "/page", nil, sample_headers, {'utm_source' => 'test'})

    # Should not crash the application
    assert_nothing_raised do
      ActiveAnalytics.queue_request(req)
    end

  ensure
    # Restore original Redis connection
    ActiveAnalytics.redis = original_redis
  end

  private

  def sample_headers
    {"User-Agent" => "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"}
  end
end
