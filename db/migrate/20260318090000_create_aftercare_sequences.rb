class CreateAftercareSequences < ActiveRecord::Migration[7.1]
  def change
    create_table :aftercare_sequences do |t|
      t.references :account, null: true, foreign_key: true
      t.string :code, null: false
      t.string :name, null: false
      t.text :description
      t.string :channel_scope, null: false, default: 'messenger_instagram'
      t.string :opt_in_topic, null: false
      t.string :default_timezone, null: false, default: 'Asia/Bangkok'
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :aftercare_sequences, :code, unique: true

    create_table :aftercare_sequence_steps do |t|
      t.references :aftercare_sequence, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :title, null: false
      t.text :instructions
      t.integer :offset_minutes, null: false
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end
    add_index :aftercare_sequence_steps, [:aftercare_sequence_id, :position], unique: true, name: 'index_aftercare_sequence_steps_on_sequence_and_position'

    create_table :aftercare_enrollments do |t|
      t.references :account, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.references :aftercare_sequence, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.integer :status, null: false, default: 0
      t.string :channel_type, null: false
      t.string :channel_key, null: false
      t.text :staff_note
      t.string :timezone_name, null: false
      t.datetime :anchor_at, null: false
      t.string :eligibility_status
      t.string :eligibility_reason
      t.datetime :eligible_until_at
      t.string :idempotency_key, null: false
      t.datetime :activated_at
      t.datetime :paused_at
      t.datetime :cancelled_at
      t.text :last_error

      t.timestamps
    end
    add_index :aftercare_enrollments, [:account_id, :idempotency_key], unique: true

    create_table :aftercare_enrollment_steps do |t|
      t.references :aftercare_enrollment, null: false, foreign_key: true
      t.references :aftercare_sequence_step, null: true, foreign_key: true
      t.integer :position, null: false
      t.string :title, null: false
      t.text :instructions
      t.integer :status, null: false, default: 0
      t.integer :draft_status, null: false, default: 0
      t.integer :offset_minutes, null: false
      t.datetime :scheduled_for, null: false
      t.text :step_note
      t.boolean :enabled, null: false, default: true
      t.text :last_error

      t.timestamps
    end
    add_index :aftercare_enrollment_steps, [:aftercare_enrollment_id, :position], unique: true, name: 'index_aftercare_enrollment_steps_on_enrollment_and_position'

    create_table :aftercare_opt_in_subscriptions do |t|
      t.references :aftercare_enrollment, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.string :topic, null: false
      t.string :provider, null: false, default: 'meta'
      t.string :capability_status, null: false, default: 'supported'
      t.string :token_ref
      t.datetime :requested_at
      t.datetime :subscribed_at
      t.datetime :expires_at
      t.datetime :revoked_at
      t.jsonb :webhook_payload, null: false, default: {}
      t.text :last_error

      t.timestamps
    end
    add_index :aftercare_opt_in_subscriptions, :aftercare_enrollment_id, unique: true, name: 'index_aftercare_opt_in_subscriptions_on_enrollment_id'

    create_table :aftercare_audit_events do |t|
      t.references :account, null: false, foreign_key: true
      t.references :aftercare_enrollment, null: true, foreign_key: true
      t.references :actor, polymorphic: true, null: true
      t.string :event_type, null: false
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    reversible do |dir|
      dir.up do
        now = Time.current
        timestamp = now.utc.strftime('%Y-%m-%d %H:%M:%S')

        execute <<~SQL.squish
          INSERT INTO aftercare_sequences
            (code, name, description, channel_scope, opt_in_topic, default_timezone, active, created_at, updated_at)
          VALUES
            ('post_purchase_checkin', 'Chăm sóc sau mua', 'Chuỗi hỏi thăm và đồng hành sau khi khách vừa mua.', 'messenger_instagram', 'aftercare.post_purchase_checkin', 'Asia/Bangkok', TRUE, '#{timestamp}', '#{timestamp}'),
            ('post_purchase_retention', 'Giữ chân sau mua', 'Chuỗi nhắc triển khai và theo dõi kết quả ngắn hạn.', 'messenger_instagram', 'aftercare.post_purchase_retention', 'Asia/Bangkok', TRUE, '#{timestamp}', '#{timestamp}')
        SQL

        post_purchase_checkin_id = select_value("SELECT id FROM aftercare_sequences WHERE code = 'post_purchase_checkin'")
        post_purchase_retention_id = select_value("SELECT id FROM aftercare_sequences WHERE code = 'post_purchase_retention'")

        execute <<~SQL.squish
          INSERT INTO aftercare_sequence_steps
            (aftercare_sequence_id, position, title, instructions, offset_minutes, enabled, created_at, updated_at)
          VALUES
            (#{post_purchase_checkin_id}, 1, 'Hỏi thăm ngày 1', 'Hỏi khách trải nghiệm sau khi mua và nhắc bước bắt đầu an toàn.', 1440, TRUE, '#{timestamp}', '#{timestamp}'),
            (#{post_purchase_checkin_id}, 2, 'Nhắc triển khai ngày 3', 'Theo dõi xem khách đã bắt đầu dùng sản phẩm/chương trình chưa.', 4320, TRUE, '#{timestamp}', '#{timestamp}'),
            (#{post_purchase_checkin_id}, 3, 'Theo dõi tuần đầu', 'Hỏi nhanh kết quả ban đầu và gợi ý bước tiếp theo.', 10080, TRUE, '#{timestamp}', '#{timestamp}'),
            (#{post_purchase_retention_id}, 1, 'Kiểm tra tiến độ', 'Nhắc khách cập nhật tiến độ sử dụng sau mua.', 2880, TRUE, '#{timestamp}', '#{timestamp}'),
            (#{post_purchase_retention_id}, 2, 'Theo dõi khó khăn', 'Chủ động hỏi xem khách có vướng mắc gì trong quá trình dùng.', 10080, TRUE, '#{timestamp}', '#{timestamp}')
        SQL
      end
    end
  end
end
