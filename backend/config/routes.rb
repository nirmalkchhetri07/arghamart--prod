Rails.application.routes.draw do
  Spree::Core::Engine.add_routes do
    # Admin authentication
    devise_for(
      Spree.admin_user_class.model_name.singular_route_key,
      class_name: Spree.admin_user_class.to_s,
      controllers: {
        sessions: 'spree/admin/user_sessions',
        passwords: 'spree/admin/user_passwords'
      },
      skip: :registrations,
      path: :admin_user,
      router_name: :spree
    )

    # "Delivered" tracking action for shipments (see
    # Spree::Admin::ShipmentsControllerDecorator). Reopening the resource
    # only adds this member route — existing shipment routes are untouched.
    #
    # Manual QR review actions (see Spree::Admin::PaymentsControllerDecorator)
    # and the storefront proof endpoints (see the ManualQrProofs controllers)
    # follow the same pattern: only additive member routes, no gem routes
    # are reopened or removed.
    namespace :admin, path: Spree.admin_path do
      resources :orders do
        resources :shipments, only: [] do
          member do
            post :mark_as_delivered
            post :send_to_ncm
          end
        end
        resources :payments, only: [] do
          member do
            put :approve
            put :reject
            get :proof
          end
        end
      end

      # Nepal delivery geography (Parts 3-4). Custom pages, additive only —
      # no gem routes reopened or removed.
      get 'manage-address', to: 'provinces#index', as: :manage_address
      get 'manage-fee', to: 'district_fees#index', as: :manage_fee
      resources :delivery_partners, only: %i[index] do
        member do
          get :edit
          patch :update
        end
        collection do
          post :test_connection
        end
      end
      resources :provinces, only: %i[update]
      resources :districts, only: %i[create update destroy] do
        member do
          post :activate
          post :deactivate
        end
      end
      resources :district_fees, only: %i[update] do
        # Collection routes MUST come before the POST member route below —
        # otherwise POST /district_fees/bulk_update matches POST /:id
        # (id="bulk_update") and returns 404.
        collection do
          post :bulk_update
          post :set_province_fee
          post :update_default_fee
        end
        # Per-row Save buttons live inside the bulk form (which is POST), so
        # they POST via `formaction` to the member path. Accept POST here in
        # addition to the default PATCH/PUT from `only: %i[update]`.
        member do
          post :update
        end
      end

      # Social Login providers (see Spree::Admin::OauthProvidersController).
      # Custom pages, additive only — no gem routes reopened or removed.
      get 'social-login', to: 'oauth_providers#index', as: :social_login
      resources :oauth_providers, only: %i[new create edit update destroy] do
        member do
          post :toggle
        end
      end
    end

    namespace :api do
      namespace :v3 do
        namespace :store do
          namespace :nepal do
            resources :provinces, only: %i[index]
          end
          resources :carts, only: [] do
            resources :payment_sessions, only: [] do
              member do
                post :proof, to: 'carts/manual_qr_proofs#create'
              end
            end
          end
          resources :orders, only: [] do
            member do
              post :manual_qr_proof, to: 'manual_qr_proofs#reupload'
            end
            resources :payments, only: [] do
              member do
                get :proof, to: 'manual_qr_proofs#show'
              end
            end
          end
          # Social Login (see Spree::Api::V3::Store::OauthProvidersController
          # and ::OauthController). The :provider constraint keeps this from
          # ever shadowing the stock auth/login|refresh|logout routes; the
          # explicit complete route must stay first so provider='complete'
          # can never reach the login action.
          resources :oauth_providers, only: %i[index]
          post 'auth/complete', to: 'oauth#complete'
          post 'auth/:provider', to: 'oauth#create',
                                 constraints: { provider: %r{(?!login|refresh|logout|complete)[a-z_]+} }
          # Facebook data-deletion callback (see
          # Spree::Api::V3::Store::FacebookDataDeletionsController).
          post 'facebook/data_deletion', to: 'facebook_data_deletions#create'
        end
      end
    end
  end
  # This line mounts Spree's routes at the root of your application.
  # This means, any requests to URLs such as /products, will go to
  # Spree::ProductsController.
  # If you would like to change where this engine is mounted, simply change the
  # :at option to something different.
  #
  # We ask that you don't use the :as option here, as Spree relies on it being
  # the default of "spree".
  mount Spree::Core::Engine, at: '/'
  post 'webhooks/ncm/:secret', to: 'webhooks/ncm#create'
  devise_for :admin_users, class_name: "Spree::AdminUser"
  devise_for :users, class_name: "Spree::User"

  # Job dashboard (Mission Control) — inspect, retry, and discard Solid Queue
  # jobs at http://localhost:3000/jobs. Guarded by its own HTTP Basic auth
  # (see config/application.rb), independent of app sessions.
  mount MissionControl::Jobs::Engine, at: "/jobs"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root to: redirect('/admin')
end
