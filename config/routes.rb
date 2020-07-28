UserService::Engine.routes.draw do
  get '/authenticate', to: 'authentication#user_info'
  post '/login', to: 'authentication#login'
  post '/logout', to: 'authentication#logout'

  resources :users do
    post :signup, on: :collection

    # all the below actions are done on collection instead of member
    # because we don't want to set_user based on user_id!
    # it's more secure to set it based on current user, if possible

    post :update_account, on: :collection
    post :forgot_password, on: :collection
    post :resend_confirmation, on: :collection
    post :update_seller, on: :member
    post :accept_invitation, on: :collection
    post :confirm_admin_invitation, on: :collection
    post :update_lost_password, on: :collection
    post :remove_from_supplier, on: :member

    get :confirm_email, on: :collection
    get :unlock_account, on: :collection
    get :approve_buyer, on: :collection
    get :seller_owners, on: :collection
    get :get_by_id, on: :collection
    get :get_by_email, on: :collection
  end

  resources :members, only: [:index, :create]

  # remove this line when pretender is taken out also DEVISE_FOR_ROUTE will be removed
  # from backend env files
  devise_for :users, only: [] if ENV['DEVISE_FOR_ROUTE'] || Rails.env.production?
end
