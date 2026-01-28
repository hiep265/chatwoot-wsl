class Captain::AssistantPolicy < ApplicationPolicy
  def index?
    true
  end

  def semantic_search?
    true
  end

  def show?
    true
  end

  def tools?
    true
  end

  def create?
    true
  end

  def update?
    true
  end

  def destroy?
    true
  end

  def playground?
    true
  end

  def scan_answer?
    true
  end

  def scan_all_pending?
    true
  end
end
