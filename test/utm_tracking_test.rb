require "test_helper"

class UtmTrackingTest < ActiveSupport::TestCase
  Request = Struct.new(:host, :path, :referrer, :headers, :query_parameters)

  def test_record_request_with_utm_parameters
    req = utm_request("google", "cpc", "summer_sale", "marketing automation", "button1")

    assert_difference("ActiveAnalytics::ViewsPerDay.count") do
      ActiveAnalytics.record_request(req)
    end

    record = ActiveAnalytics::ViewsPerDay.last
    assert_equal "google", record.utm_source
    assert_equal "cpc", record.utm_medium
    assert_equal "summer_sale", record.utm_campaign
    assert_equal "marketing automation", record.utm_term
    assert_equal "button1", record.utm_content
  end

  def test_record_request_with_partial_utm_parameters
    req = utm_request("newsletter", "email", "weekly_update", nil, nil)

    assert_difference("ActiveAnalytics::ViewsPerDay.count") do
      ActiveAnalytics.record_request(req)
    end

    record = ActiveAnalytics::ViewsPerDay.last
    assert_equal "newsletter", record.utm_source
    assert_equal "email", record.utm_medium
    assert_equal "weekly_update", record.utm_campaign
    assert_nil record.utm_term
    assert_nil record.utm_content
  end

  def test_record_request_without_utm_parameters
    req = Request.new("site.test", "/page", nil, sample_headers, {})

    assert_difference("ActiveAnalytics::ViewsPerDay.count") do
      ActiveAnalytics.record_request(req)
    end

    record = ActiveAnalytics::ViewsPerDay.last
    assert_nil record.utm_source
    assert_nil record.utm_medium
    assert_nil record.utm_campaign
    assert_nil record.utm_term
    assert_nil record.utm_content
  end

  def test_queue_request_with_utm_parameters
    req = utm_request("facebook", "social", "brand_awareness", nil, "post1")

    ActiveAnalytics.redis.del(ActiveAnalytics::PAGE_QUEUE)
    ActiveAnalytics.redis.del(ActiveAnalytics::OLD_PAGE_QUEUE)

    ActiveAnalytics.queue_request(req)

    assert_equal 1, ActiveAnalytics.redis.hlen(ActiveAnalytics::PAGE_QUEUE)

    assert_difference("ActiveAnalytics::ViewsPerDay.count") do
      ActiveAnalytics.flush_queue
    end

    record = ActiveAnalytics::ViewsPerDay.last
    assert_equal "facebook", record.utm_source
    assert_equal "social", record.utm_medium
    assert_equal "brand_awareness", record.utm_campaign
    assert_nil record.utm_term
    assert_equal "post1", record.utm_content
  end

  def test_group_by_utm_source
    create_utm_record("google", "cpc", "campaign1", 10)
    create_utm_record("facebook", "social", "campaign2", 5)
    create_utm_record("google", "email", "campaign3", 3)

    results = ActiveAnalytics::ViewsPerDay.group_by_utm_source

    assert_equal 2, results.length
    google_result = results.find { |r| r.value == "google" }
    facebook_result = results.find { |r| r.value == "facebook" }

    assert_equal 13, google_result.total
    assert_equal 5, facebook_result.total
  end

  def test_group_by_utm_medium
    create_utm_record("google", "cpc", "campaign1", 8)
    create_utm_record("facebook", "cpc", "campaign2", 4)
    create_utm_record("newsletter", "email", "campaign3", 6)

    results = ActiveAnalytics::ViewsPerDay.group_by_utm_medium

    assert_equal 2, results.length
    cpc_result = results.find { |r| r.value == "cpc" }
    email_result = results.find { |r| r.value == "email" }

    assert_equal 12, cpc_result.total
    assert_equal 6, email_result.total
  end

  def test_group_by_utm_campaign
    create_utm_record("google", "cpc", "summer_sale", 12)
    create_utm_record("facebook", "social", "summer_sale", 8)
    create_utm_record("google", "cpc", "winter_sale", 5)

    results = ActiveAnalytics::ViewsPerDay.group_by_utm_campaign

    assert_equal 2, results.length
    summer_result = results.find { |r| r.value == "summer_sale" }
    winter_result = results.find { |r| r.value == "winter_sale" }

    assert_equal 20, summer_result.total
    assert_equal 5, winter_result.total
  end

  private

  def utm_request(source, medium, campaign, term, content)
    query_params = {}
    query_params['utm_source'] = source if source
    query_params['utm_medium'] = medium if medium
    query_params['utm_campaign'] = campaign if campaign
    query_params['utm_term'] = term if term
    query_params['utm_content'] = content if content

    Request.new("site.test", "/page", nil, sample_headers, query_params)
  end

  def create_utm_record(source, medium, campaign, total)
    ActiveAnalytics::ViewsPerDay.create!(
      site: "site.test",
      page: "/page",
      date: Date.today,
      total: total,
      utm_source: source,
      utm_medium: medium,
      utm_campaign: campaign
    )
  end

  def sample_headers
    {"User-Agent" => "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"}
  end
end
