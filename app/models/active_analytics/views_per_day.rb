module ActiveAnalytics
  class ViewsPerDay < ApplicationRecord
    validates_presence_of :site, :page, :date

    scope :between_dates, -> (from, to) { where("date BETWEEN ? AND ?", from, to) }
    scope :after, -> (date) { where("date > ?", date) }
    scope :order_by_totals, -> { order(Arel.sql("SUM(total) DESC")) }
    scope :order_by_date, -> { order(:date) }
    scope :top, -> (n = 10) { order_by_totals.limit(n) }

    class Site
      attr_reader :host, :total
      def initialize(host, total)
        @host, @total = host, total
      end
    end

    class Page
      attr_reader :host, :path, :total
      def initialize(host, path, total)
        @host, @path, @total = host, path, total
      end

      def url
        host + path
      end
    end

    class UtmData
      attr_reader :value, :total, :percentage
      def initialize(value, total, total_sum = nil)
        @value, @total = value, total
        @percentage = total_sum && total_sum > 0 ? (total.to_f / total_sum * 100).round(1) : 0
      end

      def percentage_display
        "#{percentage}%"
      end
    end

    class CampaignPerformance
      attr_reader :campaign, :source, :medium, :total, :pages_count, :avg_per_page

      def initialize(campaign, source, medium, total, pages_count)
        @campaign, @source, @medium, @total, @pages_count = campaign, source, medium, total, pages_count
        @avg_per_page = pages_count > 0 ? (total.to_f / pages_count).round(1) : 0
      end

      def source_medium
        "#{source} / #{medium}".gsub(/\A\s*\/\s*|\s*\/\s*\z/, '').presence || 'Direct'
      end
    end

    def self.group_by_site
      group(:site).pluck("site, SUM(total)").map do |row|
        Site.new(row[0], row[1])
      end
    end

    def self.group_by_page
      group(:site, :page).pluck("site, page, SUM(total)").map do |row|
        Page.new(row[0], row[1], row[2])
      end
    end

    def self.group_by_referrer_site
      group(:referrer_host).pluck("referrer_host, SUM(total)").map do |row|
        Site.new(row[0], row[1])
      end
    end

    def self.group_by_referrer_page
      group(:referrer_host, :referrer_path).pluck("referrer_host, referrer_path, SUM(total)").map do |row|
        Page.new(row[0], row[1], row[2])
      end
    end

    def self.group_by_date
      group(:date).select("date, sum(total) AS total")
    end

    def self.group_by_utm_source
      utm_scope = where.not(utm_source: [nil, ""])
      total_sum = utm_scope.sum(:total)
      utm_scope.group(:utm_source).pluck("utm_source, SUM(total)").map do |row|
        UtmData.new(row[0], row[1], total_sum)
      end
    end

    def self.group_by_utm_medium
      utm_scope = where.not(utm_medium: [nil, ""])
      total_sum = utm_scope.sum(:total)
      utm_scope.group(:utm_medium).pluck("utm_medium, SUM(total)").map do |row|
        UtmData.new(row[0], row[1], total_sum)
      end
    end

    def self.group_by_utm_campaign
      utm_scope = where.not(utm_campaign: [nil, ""])
      total_sum = utm_scope.sum(:total)
      utm_scope.group(:utm_campaign).pluck("utm_campaign, SUM(total)").map do |row|
        UtmData.new(row[0], row[1], total_sum)
      end
    end

    def self.group_by_utm_term
      utm_scope = where.not(utm_term: [nil, ""])
      total_sum = utm_scope.sum(:total)
      utm_scope.group(:utm_term).pluck("utm_term, SUM(total)").map do |row|
        UtmData.new(row[0], row[1], total_sum)
      end
    end

    def self.group_by_utm_content
      utm_scope = where.not(utm_content: [nil, ""])
      total_sum = utm_scope.sum(:total)
      utm_scope.group(:utm_content).pluck("utm_content, SUM(total)").map do |row|
        UtmData.new(row[0], row[1], total_sum)
      end
    end

    def self.campaign_performance_analysis
      where.not(utm_campaign: [nil, ""])
        .group(:utm_campaign, :utm_source, :utm_medium)
        .select("utm_campaign, utm_source, utm_medium, SUM(total) as total_views, COUNT(DISTINCT page) as pages_count")
        .order("total_views DESC")
        .map do |row|
          CampaignPerformance.new(
            row.utm_campaign,
            row.utm_source,
            row.utm_medium,
            row.total_views,
            row.pages_count
          )
        end
    end

    def self.utm_overview_stats
      total_views = sum(:total)
      utm_views = where.not(utm_source: [nil, ""]).sum(:total)

      {
        total_views: total_views,
        utm_views: utm_views,
        utm_percentage: total_views > 0 ? (utm_views.to_f / total_views * 100).round(1) : 0,
        unique_campaigns: where.not(utm_campaign: [nil, ""]).distinct.count(:utm_campaign),
        unique_sources: where.not(utm_source: [nil, ""]).distinct.count(:utm_source),
        top_landing_page: group(:page).order("SUM(total) DESC").where.not(utm_source: [nil, ""]).limit(1).pluck(:page).first
      }
    end

    def self.to_histogram
      Histogram.new(self)
    end

    def self.append(params)
      total = params.delete(:total) || 1
      params[:site] = params[:site].downcase if params[:site]
      params[:referrer_path] = nil if params[:referrer_path].blank?
      params[:referrer_path] = params[:referrer_path].downcase if params[:referrer_path]
      params[:referrer_host] = params[:referrer_host].downcase if params[:referrer_host]
      where(params).first.try(:increment!, :total, total) || create!(params.merge(total: total))
    end

    SLASH = "/"

    def self.split_referrer(referrer)
      return [nil, nil] if referrer.blank?
      if (uri = URI(referrer)).host.present?
        [uri.host, uri.path.presence]
      else
        strings = referrer.split(SLASH, 2)
        [strings[0], strings[1] ? SLASH + strings[1] : nil]
      end
    end
  end
end
