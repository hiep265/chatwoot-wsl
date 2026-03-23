class CreateAftercareDispatchLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :aftercare_dispatch_logs do |t|
      t.references :aftercare_enrollment, null: false, foreign_key: true
      t.references :aftercare_enrollment_step, null: false, foreign_key: true
      t.references :message, null: true, foreign_key: true
      t.string :attempt_key, null: false
      t.string :status, null: false
      t.string :provider, null: false, default: 'meta'
      t.string :provider_message_id
      t.datetime :sent_at
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :aftercare_dispatch_logs,
              [:aftercare_enrollment_step_id, :attempt_key],
              unique: true,
              name: 'index_aftercare_dispatch_logs_on_step_and_attempt_key'
  end
end
