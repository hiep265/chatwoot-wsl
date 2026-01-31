# frozen_string_literal: true

module Api
  module V1
    module Accounts
      module Contacts
        class MemoriesController < Api::V1::Accounts::BaseController
          before_action :fetch_contact
          
          # GET /api/v1/accounts/:account_id/contacts/:contact_id/memories
          # Liệt kê memories của contact
          def index
            memories = @contact.contact_memories
                               .order(created_at: :desc)
            
            # Filter by category nếu có
            memories = memories.where(category: params[:category]) if params[:category].present?
            
            memories = memories.page(params[:page] || 1)
                               .per(params[:per_page] || 20)
            
            render json: {
              data: memories.as_json(
                only: [:id, :content, :category, :metadata, :created_at]
              ),
              meta: pagination_meta(memories)
            }
          end
          
          # POST /api/v1/accounts/:account_id/contacts/:contact_id/memories
          # Thêm memory mới
          def create
            service = ContactMemoryService.new(@contact)
            memory = service.add_memory(
              params[:content],
              category: params[:category] || 'fact',
              metadata: params[:metadata] || {}
            )
            
            if memory
              render json: { 
                success: true, 
                data: memory.as_json(
                  only: [:id, :content, :category, :metadata, :created_at]
                )
              }, status: :created
            else
              render json: { 
                success: false, 
                error: 'Failed to create memory' 
              }, status: :unprocessable_entity
            end
          end
          
          # POST /api/v1/accounts/:account_id/contacts/:contact_id/memories/search
          # Hybrid search BM25 + Semantic
          def search
            if params[:query].blank?
              return render json: { 
                error: 'Query parameter is required' 
              }, status: :bad_request
            end
            
            service = ContactMemoryService.new(@contact)
            results = service.search(
              params[:query],
              limit: params[:limit]&.to_i || 5,
              vector_weight: params[:vector_weight]&.to_f || 0.7,
              text_weight: params[:text_weight]&.to_f || 0.3
            )
            
            render json: {
              query: params[:query],
              contact_id: @contact.id,
              results_count: results.length,
              results: results.map do |r|
                {
                  id: r[:memory].id,
                  content: r[:memory].content,
                  category: r[:memory].category,
                  final_score: r[:final_score],
                  vector_score: r[:vector_score],
                  bm25_score: r[:bm25_score],
                  metadata: r[:memory].metadata,
                  created_at: r[:memory].created_at.iso8601
                }
              end
            }
          end
          
          # DELETE /api/v1/accounts/:account_id/contacts/:contact_id/memories/:id
          def destroy
            memory = @contact.contact_memories.find_by(id: params[:id])
            
            unless memory
              return render json: { error: 'Memory not found' }, status: :not_found
            end
            
            memory.destroy
            head :no_content
          end
          
          # GET /api/v1/accounts/:account_id/contacts/:contact_id/memories/stats
          # Stats về memories
          def stats
            stats = @contact.contact_memories.group(:category).count
            
            render json: {
              contact_id: @contact.id,
              total_memories: @contact.contact_memories.count,
              by_category: stats,
              last_updated: @contact.contact_memories.maximum(:created_at)&.iso8601
            }
          end
          
          private
          
          def fetch_contact
            @contact = Current.account.contacts.find(params[:contact_id])
          rescue ActiveRecord::RecordNotFound
            render json: { error: 'Contact not found' }, status: :not_found
          end
          
          def pagination_meta(resources)
            {
              current_page: resources.current_page,
              next_page: resources.next_page,
              prev_page: resources.prev_page,
              total_pages: resources.total_pages,
              total_count: resources.total_count
            }
          end
        end
      end
    end
  end
end
