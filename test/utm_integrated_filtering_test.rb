require "test_helper"

class UtmIntegratedFilteringTest < ActiveSupport::TestCase
  def setup
    # Clean database
    ActiveAnalytics::ViewsPerDay.delete_all
    ActiveAnalytics::BrowsersPerDay.delete_all

    # Create test data
    create_test_data
  end

  def test_utm_filtering_scopes_all_data
    # Test that UTM filtering applies to all analytics
    scope = ActiveAnalytics::ViewsPerDay.where(utm_source: "google")

    # Should filter pages correctly
    pages = scope.group_by_page
    assert pages.all? { |page| page.host == "site.test" }

    # Should filter referrers correctly
    referrers = scope.group_by_referrer_site
    assert_equal 1, referrers.length
    assert_equal "example.com", referrers.first.host

    # Should filter date-based data correctly
    histogram_data = scope.group_by_date
    assert histogram_data.all? { |entry| entry.total > 0 }
  end

  def test_multiple_utm_filters
    # Test combining multiple UTM parameters
    scope = ActiveAnalytics::ViewsPerDay
      .where(utm_source: "google")
      .where(utm_campaign: "summer_sale")

    assert_equal 100, scope.sum(:total)

    pages = scope.group_by_page
    assert_equal 1, pages.length
    assert_equal "/products", pages.first.path
  end

  def test_utm_filter_statistics
    all_views = ActiveAnalytics::ViewsPerDay.sum(:total)
    utm_views = ActiveAnalytics::ViewsPerDay.where(utm_source: "google").sum(:total)

    percentage = (utm_views.to_f / all_views * 100).round(1)

    assert_equal 200, all_views
    assert_equal 100, utm_views
    assert_equal 50.0, percentage
  end

  def test_utm_overview_stats
    stats = ActiveAnalytics::ViewsPerDay.utm_overview_stats

    assert_equal 200, stats[:total_views]
    assert_equal 150, stats[:utm_views]  # Google + Facebook UTM traffic
    assert_equal 75.0, stats[:utm_percentage]
    assert_equal 2, stats[:unique_campaigns]  # summer_sale, brand_awareness
    assert_equal 2, stats[:unique_sources]    # google, facebook
    assert_equal "/products", stats[:top_landing_page]
  end

  def test_campaign_performance_analysis
    performance = ActiveAnalytics::ViewsPerDay.campaign_performance_analysis

    assert_equal 2, performance.length

    summer_campaign = performance.find { |p| p.campaign == "summer_sale" }
    brand_campaign = performance.find { |p| p.campaign == "brand_awareness" }

    assert_equal "google", summer_campaign.source
    assert_equal "cpc", summer_campaign.medium
    assert_equal 100, summer_campaign.total
    assert_equal 1, summer_campaign.pages_count

    assert_equal "facebook", brand_campaign.source
    assert_equal "social", brand_campaign.medium
    assert_equal 50, brand_campaign.total
    assert_equal 2, brand_campaign.pages_count
  end

  def test_utm_data_with_percentages
    utm_sources = ActiveAnalytics::ViewsPerDay.group_by_utm_source

    assert_equal 2, utm_sources.length

    google_source = utm_sources.find { |s| s.value == "google" }
    facebook_source = utm_sources.find { |s| s.value == "facebook" }

    # Google: 100 out of 150 UTM views = 66.7%
    assert_equal 66.7, google_source.percentage
    assert_equal "66.7%", google_source.percentage_display

    # Facebook: 50 out of 150 UTM views = 33.3%
    assert_equal 33.3, facebook_source.percentage
    assert_equal "33.3%", facebook_source.percentage_display
  end

  def test_filter_with_no_results
    # Test filtering by non-existent UTM parameter
    scope = ActiveAnalytics::ViewsPerDay.where(utm_source: "nonexistent")

    assert_equal 0, scope.sum(:total)
    assert_equal [], scope.group_by_page
    assert_equal [], scope.group_by_utm_campaign
  end

  def test_utm_filtering_preserves_date_filtering
    # Test that UTM filtering works with date ranges
    yesterday = Date.yesterday
    today = Date.today

    # Create data for different dates
    ActiveAnalytics::ViewsPerDay.create!(
      site: "site.test",
      page: "/old-page",
      date: yesterday,
      total: 25,
      utm_source: "google",
      utm_campaign: "old_campaign"
    )

    # Filter by UTM and date
    scope = ActiveAnalytics::ViewsPerDay
      .where(utm_source: "google")
      .where(date: today)

    # Should only get today's data
    assert_equal 100, scope.sum(:total)  # Only today's Google data

    pages = scope.group_by_page
    assert_equal 1, pages.length
    assert_equal "/products", pages.first.path  # Not the old page
  end

  def test_nested_utm_filtering
    # Test filtering within already filtered results
    base_scope = ActiveAnalytics::ViewsPerDay.where(utm_source: "facebook")

    # Further filter by campaign
    campaign_scope = base_scope.where(utm_campaign: "brand_awareness")

    assert_equal 50, base_scope.sum(:total)
    assert_equal 50, campaign_scope.sum(:total)  # All Facebook traffic is brand_awareness

    # Further filter by medium
    medium_scope = campaign_scope.where(utm_medium: "social")
    assert_equal 50, medium_scope.sum(:total)
  end

  private

  def create_test_data
    # Google Ads traffic
    ActiveAnalytics::ViewsPerDay.create!(
      site: "site.test",
      page: "/products",
      date: Date.today,
      total: 100,  # Increased from 50 to 100
      referrer_host: "example.com",
      referrer_path: "/search",
      utm_source: "google",
      utm_medium: "cpc",
      utm_campaign: "summer_sale",
      utm_term: "widgets",
      utm_content: "ad1"
    )

    # Facebook Social traffic - Page 1
    ActiveAnalytics::ViewsPerDay.create!(
      site: "site.test",
      page: "/about",
      date: Date.today,
      total: 30,  # Decreased from 60 to 30
      referrer_host: "example.com",
      referrer_path: "/social",
      utm_source: "facebook",
      utm_medium: "social",
      utm_campaign: "brand_awareness"
    )

    # Facebook Social traffic - Page 2
    ActiveAnalytics::ViewsPerDay.create!(
      site: "site.test",
      page: "/contact",
      date: Date.today,
      total: 20,  # Decreased from 40 to 20
      referrer_host: "example.com",
      referrer_path: "/social",
      utm_source: "facebook",
      utm_medium: "social",
      utm_campaign: "brand_awareness"
    )

    # Direct traffic (no UTM)
    ActiveAnalytics::ViewsPerDay.create!(
      site: "site.test",
      page: "/home",
      date: Date.today,
      total: 50,
      referrer_host: nil,
      referrer_path: nil
    )
  end
end
