module ApplicationHelper
  UI_BRAND_NAME = 'TA AI TECH'.freeze

  def available_locales_with_name
    LANGUAGES_CONFIG.map { |_key, val| val.slice(:name, :iso_639_1_code) }
  end

  def feature_help_urls
    features = YAML.safe_load(Rails.root.join('config/features.yml').read).freeze
    features.each_with_object({}) do |feature, hash|
      hash[feature['name']] = feature['help_url'] if feature['help_url']
    end
  end

  def ui_brand_name(name = nil)
    display_name = name.presence ||
                   @global_config&.[]('INSTALLATION_NAME').presence ||
                   @global_config&.[]('BRAND_NAME').presence

    return UI_BRAND_NAME if display_name.blank?
    return UI_BRAND_NAME if display_name.to_s.casecmp('Chatwoot').zero?

    display_name
  end

  def ui_global_config(config)
    ui_config = (config || {}).to_h.with_indifferent_access
    display_name = ui_brand_name(
      ui_config['INSTALLATION_NAME'].presence || ui_config['BRAND_NAME']
    )

    ui_config.merge(
      'INSTALLATION_NAME' => display_name,
      'BRAND_NAME' => ui_brand_name(ui_config['BRAND_NAME'])
    )
  end
end
