# NOTE: only doing this in development as some production environments (Heroku)
# NOTE: are sensitive to local FS writes, and besides -- it's just not proper
# NOTE: to have a dev-mode tool do its thing in production.
# NOTE: auto annotation is opt-in because annotate can fail on app-specific
# NOTE: model defaults and should not block a successful migration.
if Rails.env.development? && ENV['AUTO_ANNOTATE_ON_DB_MIGRATE'] == 'true'
  require 'annotate_rb'

  migration_tasks = %w[
    db:migrate
    db:migrate:up
    db:migrate:down
    db:migrate:reset
    db:migrate:redo
    db:rollback
    db:migrate:with_data
    db:migrate:up:with_data
    db:migrate:down:with_data
    db:migrate:reset:with_data
    db:migrate:redo:with_data
    db:rollback:with_data
  ].freeze

  migration_tasks.each do |task_name|
    next unless Rake::Task.task_defined?(task_name)

    Rake::Task[task_name].enhance do
      begin
        AnnotateRb::Runner.run([
          'models',
          '--show-foreign-keys',
          '--show-indexes',
          '--hide-limit-column-types',
          'integer,bigint,boolean',
          '--hide-default-column-types',
          'json,jsonb,hstore'
        ])
      rescue StandardError => e
        warn "Skipping annotate after #{task_name}: #{e.class}: #{e.message}"
      end
    end
  end
end
