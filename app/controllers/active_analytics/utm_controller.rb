require_dependency "active_analytics/application_controller"

module ActiveAnalytics
  class UtmController < ApplicationController
    before_action :require_date_range

    def index
      @utm_sources = current_views_per_days.top(50).group_by_utm_source
      @utm_mediums = current_views_per_days.top(50).group_by_utm_medium
      @utm_campaigns = current_views_per_days.top(50).group_by_utm_campaign
      @histogram = Histogram.new(current_views_per_days.where.not(utm_source: [nil, ""]).order_by_date.group_by_date, from_date, to_date)
      @previous_histogram = Histogram.new(previous_views_per_days.where.not(utm_source: [nil, ""]).order_by_date.group_by_date, previous_from_date, previous_to_date)
    end

    def sources
      @utm_sources = current_views_per_days.top(100).group_by_utm_source
      @histogram = Histogram.new(current_views_per_days.where.not(utm_source: [nil, ""]).order_by_date.group_by_date, from_date, to_date)
      @previous_histogram = Histogram.new(previous_views_per_days.where.not(utm_source: [nil, ""]).order_by_date.group_by_date, previous_from_date, previous_to_date)
    end

    def mediums
      @utm_mediums = current_views_per_days.top(100).group_by_utm_medium
      @histogram = Histogram.new(current_views_per_days.where.not(utm_medium: [nil, ""]).order_by_date.group_by_date, from_date, to_date)
      @previous_histogram = Histogram.new(previous_views_per_days.where.not(utm_medium: [nil, ""]).order_by_date.group_by_date, previous_from_date, previous_to_date)
    end

    def campaigns
      @utm_campaigns = current_views_per_days.top(100).group_by_utm_campaign
      @histogram = Histogram.new(current_views_per_days.where.not(utm_campaign: [nil, ""]).order_by_date.group_by_date, from_date, to_date)
      @previous_histogram = Histogram.new(previous_views_per_days.where.not(utm_campaign: [nil, ""]).order_by_date.group_by_date, previous_from_date, previous_to_date)
    end

    def show
      @utm_type = params[:utm_type]
      @utm_value = params[:utm_value]

      case @utm_type
      when 'source'
        scope = current_views_per_days.where(utm_source: @utm_value)
        previous_scope = previous_views_per_days.where(utm_source: @utm_value)
      when 'medium'
        scope = current_views_per_days.where(utm_medium: @utm_value)
        previous_scope = previous_views_per_days.where(utm_medium: @utm_value)
      when 'campaign'
        scope = current_views_per_days.where(utm_campaign: @utm_value)
        previous_scope = previous_views_per_days.where(utm_campaign: @utm_value)
      else
        redirect_to utm_path(params[:site], from: params[:from], to: params[:to]) and return
      end

      @histogram = Histogram.new(scope.order_by_date.group_by_date, from_date, to_date)
      @previous_histogram = Histogram.new(previous_scope.order_by_date.group_by_date, previous_from_date, previous_to_date)
      @pages = scope.top(100).group_by_page
    end
  end
end
