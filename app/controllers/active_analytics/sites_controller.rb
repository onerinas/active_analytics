require_dependency "active_analytics/application_controller"

module ActiveAnalytics
  class SitesController < ApplicationController
    before_action :require_date_range, only: :show

    def index
      @sites = ViewsPerDay.after(30.days.ago).order_by_totals.group_by_site
      redirect_to(site_path(@sites.first.host)) if @sites.size == 1
    end

    def show
      # Apply UTM filters globally to all analytics
      scope = apply_utm_filters(current_views_per_days)
      previous_scope = apply_utm_filters(previous_views_per_days)

      # Core analytics with UTM filtering applied
      @histogram = Histogram.new(scope.order_by_date.group_by_date, from_date, to_date)
      @previous_histogram = Histogram.new(previous_scope.order_by_date.group_by_date, previous_from_date, previous_to_date)
      @referrers = scope.top.group_by_referrer_site
      @pages = scope.top.group_by_page
      if utm_filters.any?
        @browsers = BrowsersPerDay.for_views_scope(scope)
      else
        @browsers = BrowsersPerDay.filter_by(params).group_by_name.top
      end

      # UTM data (showing breakdown within current filters)
      @utm_sources = scope.top(10).group_by_utm_source
      @utm_campaigns = scope.top(10).group_by_utm_campaign
      @utm_mediums = scope.top(10).group_by_utm_medium

      # Filter state tracking
      @active_utm_filters = utm_filters
      @filtered_total_views = scope.sum(:total)
      @unfiltered_total_views = current_views_per_days.sum(:total)
      @filter_percentage = @unfiltered_total_views > 0 ?
        (@filtered_total_views.to_f / @unfiltered_total_views * 100).round(1) : 0
    end

    private

    def apply_utm_filters(scope)
      utm_filters.each do |param, value|
        scope = scope.where(param => value) if value.present?
      end
      scope
    end

    def utm_filters
      @utm_filters ||= {
        utm_source: params[:utm_source],
        utm_medium: params[:utm_medium],
        utm_campaign: params[:utm_campaign],
        utm_term: params[:utm_term],
        utm_content: params[:utm_content]
      }.compact
    end
  end
end
