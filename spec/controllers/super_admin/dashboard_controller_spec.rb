require 'rails_helper'

RSpec.describe 'Super Admin dashboard', type: :request do
  let(:super_admin) { create(:super_admin) }

  describe 'GET /super_admin' do
    context 'when it is an unauthenticated user' do
      it 'redirects to sign in' do
        get '/super_admin'

        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated user' do
      it 'renders the dashboard' do
        sign_in(super_admin, scope: :super_admin)

        get '/super_admin'

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Super Admin Console')
      end
    end
  end
end
