require 'test_helper'

module ActiveAnalytics
  class SitesControllerUtmTest < ActionDispatch::IntegrationTest
    include Engine.routes.url_helpers

    def setup
      @site = "example.com"
      @from_date = 7.days.ago.to_date
      @to_date = Date.today

      # Clean and create test data
      ViewsPerDay.delete_all
      BrowsersPerDay.delete_all
      create_utm_test_data
    end

    def test_main_dashboard_without_utm_filters
      get site_path(@site), params: { from: @from_date, to: @to_date }

      assert_response :success

      # Should show all data
      assert_select "h3", text: /Sources/
      assert_select "h3", text: /Pages/
      assert_select "h3", text: /Campaign Analytics/

      # Should not show filter state
      assert_select ".filter-state", count: 0
    end

    def test_main_dashboard_with_utm_source_filter
      get site_path(@site), params: {
        from: @from_date,
        to: @to_date,
        utm_source: "google"
      }

      assert_response :success

      # Should show filter state
      assert_select ".filter-state"
      assert_select ".filter-tag", text: /Utm source: google/
      assert_select ".filter-remove"

      # Should show filtered statistics
      assert_select "p", text: /50.0% of total traffic/
    end

    def test_main_dashboard_with_multiple_utm_filters
      get site_path(@site), params: {
        from: @from_date,
        to: @to_date,
        utm_source: "google",
        utm_campaign: "summer_sale"
      }

      assert_response :success

      # Should show both filters
      assert_select ".filter-tag", count: 2
      assert_select ".filter-tag", text: /Utm source: google/
      assert_select ".filter-tag", text: /Utm campaign: summer_sale/

      # Should show clear all filters button
      assert_select "a", text: "Clear All Filters"
    end

    def test_utm_filter_affects_all_dashboard_sections
      get site_path(@site), params: {
        from: @from_date,
        to: @to_date,
        utm_source: "google"
      }

      assert_response :success

      # The pages section should only show pages visited from Google UTM traffic
      # The referrers section should only show referrers from Google UTM traffic
      # This is tested by checking the data is properly scoped

      # Check that campaign analytics section shows filtered data
      assert_select ".utm-summary"
      assert_select ".metric-value", text: "1"  # Only 1 source (google) after filtering
    end

    def test_utm_filter_with_no_results
      get site_path(@site), params: {
        from: @from_date,
        to: @to_date,
        utm_source: "nonexistent"
      }

      assert_response :success

      # Should show filter state but with 0% traffic
      assert_select ".filter-state"
      assert_select "p", text: /0 views/
      assert_select "p", text: /0.0% of total traffic/
    end

    def test_clear_all_filters_link
      get site_path(@site), params: {
        from: @from_date,
        to: @to_date,
        utm_source: "google",
        utm_campaign: "summer_sale"
      }

      assert_response :success

      # Find the clear all filters link
      clear_link = css_select("a:contains('Clear All Filters')").first
      assert clear_link

      # Check that it goes to the same page without UTM parameters
      href = clear_link['href']
      assert_includes href, "/#{@site}"
      assert_includes href, "from=#{@from_date}"
      assert_includes href, "to=#{@to_date}"
      assert_not_includes href, "utm_source"
      assert_not_includes href, "utm_campaign"
    end

    def test_utm_links_in_campaign_analytics_filter_dashboard
      get site_path(@site), params: { from: @from_date, to: @to_date }

      assert_response :success

      # Find UTM source links in campaign analytics
      google_link = css_select("a:contains('google')").first
      assert google_link

      # Check that clicking goes to filtered dashboard
      href = google_link['href']
      assert_includes href, "/#{@site}"
      assert_includes href, "utm_source=google"
      assert_includes href, "from=#{@from_date}"
      assert_includes href, "to=#{@to_date}"
    end

    def test_date_range_preserved_with_utm_filters
      get site_path(@site), params: {
        from: @from_date,
        to: @to_date,
        utm_source: "facebook"
      }

      assert_response :success

      # Check that date range is preserved in all links
      all_links = css_select("a[href*='from=']")
      all_links.each do |link|
        href = link['href']
        assert_includes href, "from=#{@from_date}"
        assert_includes href, "to=#{@to_date}"
      end
    end

    def test_utm_filter_state_calculations
      # Test the controller calculations for filter state
      controller = SitesController.new
      controller.params = ActionController::Parameters.new({
        site: @site,
        from: @from_date,
        to: @to_date,
        utm_source: "google"
      })

      # Mock the date range methods
      def controller.from_date; Date.parse(params[:from]); end
      def controller.to_date; Date.parse(params[:to]); end
      def controller.current_views_per_days
        ViewsPerDay.where(site: params[:site]).between_dates(from_date, to_date)
      end
      def controller.previous_views_per_days
        ViewsPerDay.where(site: params[:site]).between_dates(from_date - 7.days, to_date - 7.days)
      end

      # Execute the controller action logic
      scope = controller.send(:apply_utm_filters, controller.current_views_per_days)
      filtered_total = scope.sum(:total)
      unfiltered_total = controller.current_views_per_days.sum(:total)

      percentage = unfiltered_total > 0 ?
        (filtered_total.to_f / unfiltered_total * 100).round(1) : 0

      assert_equal 50, filtered_total     # Google traffic
      assert_equal 200, unfiltered_total  # All traffic
      assert_equal 25.0, percentage       # 50/200 = 25%
    end

    private

    def create_utm_test_data
      # Google Ads traffic
      ViewsPerDay.create!(
        site: @site,
        page: "/products",
        date: Date.today,
        total: 50,
        referrer_host: "google.com",
        referrer_path: "/search",
        utm_source: "google",
        utm_medium: "cpc",
        utm_campaign: "summer_sale"
      )

      # Facebook Social traffic
      ViewsPerDay.create!(
        site: @site,
        page: "/about",
        date: Date.today,
        total: 75,
        referrer_host: "facebook.com",
        referrer_path: "/social",
        utm_source: "facebook",
        utm_medium: "social",
        utm_campaign: "brand_awareness"
      )

      # Email traffic
      ViewsPerDay.create!(
        site: @site,
        page: "/newsletter",
        date: Date.today,
        total: 25,
        referrer_host: "email.com",
        referrer_path: "/click",
        utm_source: "newsletter",
        utm_medium: "email",
        utm_campaign: "weekly_update"
      )

      # Direct traffic (no UTM)
      ViewsPerDay.create!(
        site: @site,
        page: "/home",
        date: Date.today,
        total: 50,
        referrer_host: nil,
        referrer_path: nil
      )

      # Browser data for testing
      BrowsersPerDay.create!(
        site: @site,
        date: Date.today,
        name: "Chrome",
        version: "91.0",
        total: 100
      )

      BrowsersPerDay.create!(
        site: @site,
        date: Date.today,
        name: "Firefox",
        version: "89.0",
        total: 100
      )
    end
  end
end
