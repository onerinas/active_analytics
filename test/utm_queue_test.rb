require "test_helper"

class UtmQueueTest < ActiveSupport::TestCase
  Request = Struct.new(:host, :path, :referrer, :headers, :query_parameters)

  def setup
    # Clean Redis before each test
    ActiveAnalytics.redis.del(ActiveAnalytics::PAGE_QUEUE)
    ActiveAnalytics.redis.del(ActiveAnalytics::OLD_PAGE_QUEUE)
    ActiveAnalytics.redis.del(ActiveAnalytics::BROWSER_QUEUE)
    ActiveAnalytics.redis.del(ActiveAnalytics::OLD_BROWSER_QUEUE)
  end

  def test_queue_with_referrer_and_utm
    req = utm_request("google", "cpc", "summer_sale", "keyword", "ad1", "http://google.com/search")

    ActiveAnalytics.queue_request(req)

    assert_equal 1, ActiveAnalytics.redis.hlen(ActiveAnalytics::PAGE_QUEUE)

    assert_difference("ActiveAnalytics::ViewsPerDay.count") do
      ActiveAnalytics.flush_queue
    end

    record = ActiveAnalytics::ViewsPerDay.last
    assert_equal "site.test", record.site
    assert_equal "/page", record.page
    assert_equal "google.com", record.referrer_host
    assert_equal "/search", record.referrer_path
    assert_equal "google", record.utm_source
    assert_equal "cpc", record.utm_medium
    assert_equal "summer_sale", record.utm_campaign
    assert_equal "keyword", record.utm_term
    assert_equal "ad1", record.utm_content
  end

  def test_queue_without_referrer_with_utm
    req = utm_request("newsletter", "email", "weekly", nil, "button2", nil)

    ActiveAnalytics.queue_request(req)

    assert_equal 1, ActiveAnalytics.redis.hlen(ActiveAnalytics::PAGE_QUEUE)

    assert_difference("ActiveAnalytics::ViewsPerDay.count") do
      ActiveAnalytics.flush_queue
    end

    record = ActiveAnalytics::ViewsPerDay.last
    assert_equal "site.test", record.site
    assert_equal "/page", record.page
    assert_nil record.referrer_host
    assert_nil record.referrer_path
    assert_equal "newsletter", record.utm_source
    assert_equal "email", record.utm_medium
    assert_equal "weekly", record.utm_campaign
    assert_nil record.utm_term
    assert_equal "button2", record.utm_content
  end

  def test_queue_with_referrer_without_utm
    req = Request.new("site.test", "/page", "http://example.com/path", sample_headers, {})

    ActiveAnalytics.queue_request(req)

    assert_equal 1, ActiveAnalytics.redis.hlen(ActiveAnalytics::PAGE_QUEUE)

    assert_difference("ActiveAnalytics::ViewsPerDay.count") do
      ActiveAnalytics.flush_queue
    end

    record = ActiveAnalytics::ViewsPerDay.last
    assert_equal "site.test", record.site
    assert_equal "/page", record.page
    assert_equal "example.com", record.referrer_host
    assert_equal "/path", record.referrer_path
    assert_nil record.utm_source
    assert_nil record.utm_medium
    assert_nil record.utm_campaign
    assert_nil record.utm_term
    assert_nil record.utm_content
  end

  def test_queue_without_referrer_without_utm
    req = Request.new("site.test", "/page", nil, sample_headers, {})

    ActiveAnalytics.queue_request(req)

    assert_equal 1, ActiveAnalytics.redis.hlen(ActiveAnalytics::PAGE_QUEUE)

    assert_difference("ActiveAnalytics::ViewsPerDay.count") do
      ActiveAnalytics.flush_queue
    end

    record = ActiveAnalytics::ViewsPerDay.last
    assert_equal "site.test", record.site
    assert_equal "/page", record.page
    assert_nil record.referrer_host
    assert_nil record.referrer_path
    assert_nil record.utm_source
    assert_nil record.utm_medium
    assert_nil record.utm_campaign
    assert_nil record.utm_term
    assert_nil record.utm_content
  end

  def test_queue_with_empty_utm_values
    query_params = {
      'utm_source' => '',
      'utm_medium' => 'email',
      'utm_campaign' => '',
      'utm_term' => 'test',
      'utm_content' => ''
    }
    req = Request.new("site.test", "/page", nil, sample_headers, query_params)

    ActiveAnalytics.queue_request(req)

    assert_difference("ActiveAnalytics::ViewsPerDay.count") do
      ActiveAnalytics.flush_queue
    end

    record = ActiveAnalytics::ViewsPerDay.last
    assert_nil record.utm_source  # Empty string should become nil
    assert_equal "email", record.utm_medium
    assert_nil record.utm_campaign  # Empty string should become nil
    assert_equal "test", record.utm_term
    assert_nil record.utm_content  # Empty string should become nil
  end

  def test_multiple_queue_requests_aggregation
    req1 = utm_request("google", "cpc", "campaign1", nil, nil, nil)
    req2 = utm_request("google", "cpc", "campaign1", nil, nil, nil)
    req3 = utm_request("facebook", "social", "campaign2", nil, nil, nil)

    ActiveAnalytics.queue_request(req1)
    ActiveAnalytics.queue_request(req2)
    ActiveAnalytics.queue_request(req3)

    assert_equal 2, ActiveAnalytics.redis.hlen(ActiveAnalytics::PAGE_QUEUE)

    assert_difference("ActiveAnalytics::ViewsPerDay.count", 2) do
      ActiveAnalytics.flush_queue
    end

    google_record = ActiveAnalytics::ViewsPerDay.find_by(utm_source: "google")
    facebook_record = ActiveAnalytics::ViewsPerDay.find_by(utm_source: "facebook")

    assert_equal 2, google_record.total
    assert_equal 1, facebook_record.total
  end

  def test_utm_data_class_functionality
    data = ActiveAnalytics::ViewsPerDay::UtmData.new("google", 150)
    assert_equal "google", data.value
    assert_equal 150, data.total
  end

  def test_extract_utm_parameters_method
    query_params = {
      'utm_source' => 'google',
      'utm_medium' => 'cpc',
      'utm_campaign' => 'test_campaign',
      'utm_term' => 'keyword',
      'utm_content' => 'ad_content',
      'other_param' => 'ignored'
    }

    request = Request.new("site.test", "/page", nil, sample_headers, query_params)
    utm_params = ActiveAnalytics.send(:extract_utm_parameters, request)

    assert_equal "google", utm_params[:utm_source]
    assert_equal "cpc", utm_params[:utm_medium]
    assert_equal "test_campaign", utm_params[:utm_campaign]
    assert_equal "keyword", utm_params[:utm_term]
    assert_equal "ad_content", utm_params[:utm_content]
    assert_equal 5, utm_params.keys.length  # Should only extract UTM params
  end

  def test_utm_grouping_with_order_by_totals
    create_utm_record("google", "cpc", "campaign1", 100)
    create_utm_record("facebook", "social", "campaign2", 200)
    create_utm_record("newsletter", "email", "campaign3", 50)

    # Test that results are ordered by total (descending)
    results = ActiveAnalytics::ViewsPerDay.top(10).group_by_utm_source

    assert_equal 3, results.length
    assert_equal "facebook", results[0].value
    assert_equal 200, results[0].total
    assert_equal "google", results[1].value
    assert_equal 100, results[1].total
    assert_equal "newsletter", results[2].value
    assert_equal 50, results[2].total
  end

  def test_utm_grouping_excludes_nil_and_empty
    # Create records with nil and empty UTM values
    ActiveAnalytics::ViewsPerDay.create!(
      site: "site.test", page: "/page", date: Date.today, total: 10,
      utm_source: nil, utm_medium: "email", utm_campaign: "test"
    )
    ActiveAnalytics::ViewsPerDay.create!(
      site: "site.test", page: "/page", date: Date.today, total: 20,
      utm_source: "", utm_medium: "social", utm_campaign: "test"
    )
    ActiveAnalytics::ViewsPerDay.create!(
      site: "site.test", page: "/page", date: Date.today, total: 30,
      utm_source: "google", utm_medium: "cpc", utm_campaign: "test"
    )

    results = ActiveAnalytics::ViewsPerDay.group_by_utm_source

    # Should only include the record with non-nil, non-empty utm_source
    assert_equal 1, results.length
    assert_equal "google", results[0].value
    assert_equal 30, results[0].total
  end

  private

  def utm_request(source, medium, campaign, term, content, referrer)
    query_params = {}
    query_params['utm_source'] = source if source
    query_params['utm_medium'] = medium if medium
    query_params['utm_campaign'] = campaign if campaign
    query_params['utm_term'] = term if term
    query_params['utm_content'] = content if content

    Request.new("site.test", "/page", referrer, sample_headers, query_params)
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
