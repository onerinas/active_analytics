require_dependency "active_analytics/application_controller"

module ActiveAnalytics
  class PagesController < ApplicationController
    include PagesHelper

    before_action :require_date_range

    def index
      # Apply UTM filters if provided
      scope = current_views_per_days
      previous_scope = previous_views_per_days

      if params[:utm_source].present?
        scope = scope.where(utm_source: params[:utm_source])
        previous_scope = previous_scope.where(utm_source: params[:utm_source])
      end

      if params[:utm_medium].present?
        scope = scope.where(utm_medium: params[:utm_medium])
        previous_scope = previous_scope.where(utm_medium: params[:utm_medium])
      end

      if params[:utm_campaign].present?
        scope = scope.where(utm_campaign: params[:utm_campaign])
        previous_scope = previous_scope.where(utm_campaign: params[:utm_campaign])
      end

      @histogram = Histogram.new(scope.order_by_date.group_by_date, from_date, to_date)
      @previous_histogram = Histogram.new(previous_scope.order_by_date.group_by_date, previous_from_date, previous_to_date)
      @pages = scope.top(100).group_by_page

      # Show active filters
      @active_filters = {
        utm_source: params[:utm_source],
        utm_medium: params[:utm_medium],
        utm_campaign: params[:utm_campaign]
      }.compact
    end

    def show
      page_scope = current_views_per_days.where(page: page_from_params)
      previous_page_scope = previous_views_per_days.where(page: page_from_params)
      @histogram = Histogram.new(page_scope.order_by_date.group_by_date, from_date, to_date)
      @previous_histogram = Histogram.new(previous_page_scope.order_by_date.group_by_date, previous_from_date, previous_to_date)
      @next_pages = current_views_per_days.where(referrer_host: params[:site], referrer_path: page_from_params).top(100).group_by_page
      @previous_pages = page_scope.top(100).group_by_referrer_page
    end
  end
end
