require 'test_helper'

module ActiveAnalytics
  class UtmControllerTest < ActionDispatch::IntegrationTest
    include Engine.routes.url_helpers
  def setup
    @site = "example.com"
    @from_date = 7.days.ago.to_date
    @to_date = Date.today

    # Create test data
    create_utm_data
  end

  def test_utm_index_action
    get "/#{@site}/utm", params: { from: @from_date, to: @to_date }

    assert_response :success
    assert_select "h3", text: "UTM Sources"
    assert_select "h3", text: "UTM Mediums"
    assert_select "h3", text: "UTM Campaigns"
  end

  def test_utm_sources_action
    get "/#{@site}/utm/sources", params: { from: @from_date, to: @to_date }

    assert_response :success
    assert_select "h3", text: "UTM Sources"
    assert_select "table"
  end

  def test_utm_mediums_action
    get "/#{@site}/utm/mediums", params: { from: @from_date, to: @to_date }

    assert_response :success
    assert_select "h3", text: "UTM Mediums"
    assert_select "table"
  end

  def test_utm_campaigns_action
    get "/#{@site}/utm/campaigns", params: { from: @from_date, to: @to_date }

    assert_response :success
    assert_select "h3", text: "UTM Campaigns"
    assert_select "table"
  end

  def test_utm_show_source
    get "/#{@site}/utm/source/google", params: { from: @from_date, to: @to_date }

    assert_response :success
    assert_select "h3", text: "UTM Source: google"
  end

  def test_utm_show_medium
    get "/#{@site}/utm/medium/cpc", params: { from: @from_date, to: @to_date }

    assert_response :success
    assert_select "h3", text: "UTM Medium: cpc"
  end

  def test_utm_show_campaign
    get "/#{@site}/utm/campaign/summer_sale", params: { from: @from_date, to: @to_date }

    assert_response :success
    assert_select "h3", text: "UTM Campaign: summer_sale"
  end

  def test_utm_show_invalid_type
    get "/#{@site}/utm/invalid/value", params: { from: @from_date, to: @to_date }

    assert_redirected_to "/#{@site}/utm?from=#{@from_date}&to=#{@to_date}"
  end

  def test_utm_index_with_no_utm_data
    # Clear all UTM data
    ActiveAnalytics::ViewsPerDay.where.not(utm_source: nil).destroy_all

    get "/#{@site}/utm", params: { from: @from_date, to: @to_date }

    assert_response :success
    # Should still render but with empty data
    assert_select "h3", text: "UTM Sources"
  end

  def test_date_range_filtering
    # Create data outside the date range
    ActiveAnalytics::ViewsPerDay.create!(
      site: @site,
      page: "/page",
      date: 30.days.ago,
      total: 100,
      utm_source: "old_source",
      utm_medium: "old_medium",
      utm_campaign: "old_campaign"
    )

    get "/#{@site}/utm", params: { from: @from_date, to: @to_date }

    assert_response :success
    # The old data should not appear in the current date range
    assert_no_match(/old_source/, response.body)
  end

  private

  def create_utm_data
    # Create various UTM records for testing
    ActiveAnalytics::ViewsPerDay.create!(
      site: @site,
      page: "/page1",
      date: Date.today,
      total: 50,
      utm_source: "google",
      utm_medium: "cpc",
      utm_campaign: "summer_sale"
    )

    ActiveAnalytics::ViewsPerDay.create!(
      site: @site,
      page: "/page2",
      date: Date.today,
      total: 30,
      utm_source: "facebook",
      utm_medium: "social",
      utm_campaign: "brand_awareness"
    )

    ActiveAnalytics::ViewsPerDay.create!(
      site: @site,
      page: "/page3",
      date: Date.today,
      total: 20,
      utm_source: "newsletter",
      utm_medium: "email",
      utm_campaign: "weekly_update"
    )
  end
  end
end
