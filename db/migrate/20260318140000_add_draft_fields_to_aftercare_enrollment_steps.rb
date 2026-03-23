class AddDraftFieldsToAftercareEnrollmentSteps < ActiveRecord::Migration[7.1]
  def change
    change_table :aftercare_enrollment_steps, bulk: true do |t|
      t.text :draft_body
      t.text :draft_summary
      t.string :draft_version
      t.datetime :draft_generated_at
      t.jsonb :draft_input_snapshot, null: false, default: {}
      t.text :draft_error
    end
  end
end
