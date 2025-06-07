class AddUtmSupportToActiveAnalyticsViewsPerDays < ActiveRecord::Migration[5.2]
  def change
    add_column :active_analytics_views_per_days, :utm_source, :string
    add_column :active_analytics_views_per_days, :utm_medium, :string
    add_column :active_analytics_views_per_days, :utm_campaign, :string
    add_column :active_analytics_views_per_days, :utm_term, :string
    add_column :active_analytics_views_per_days, :utm_content, :string

    # Add indexes for efficient UTM queries
    add_index :active_analytics_views_per_days, [:date, :site, :utm_source],
              name: 'index_views_per_days_on_date_site_utm_source'
    add_index :active_analytics_views_per_days, [:date, :site, :utm_medium],
              name: 'index_views_per_days_on_date_site_utm_medium'
    add_index :active_analytics_views_per_days, [:date, :site, :utm_campaign],
              name: 'index_views_per_days_on_date_site_utm_campaign'
  end
end
