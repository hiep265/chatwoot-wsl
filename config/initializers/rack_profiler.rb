# frozen_string_literal: true

if Rails.env.development? && ENV['DISABLE_MINI_PROFILER'].blank?
  require 'rack'
  # rack-mini-profiler still references Rack::File, while Rack 3 exposes Rack::Files.
  Rack.const_set(:File, Rack::Files) if defined?(Rack::Files) && !Rack.const_defined?(:File, false)
  require 'rack-mini-profiler'

  # initialization is skipped so trigger it
  Rack::MiniProfilerRails.initialize!(Rails.application)
end
