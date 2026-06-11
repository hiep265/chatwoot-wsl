require 'rails_helper'

RSpec.describe SuperAdmin::ApplicationController do
  describe 'helper exposure' do
    it 'exposes ui_brand_name to super admin views' do
      expect(described_class._helpers.instance_methods).to include(:ui_brand_name)
    end
  end
end
