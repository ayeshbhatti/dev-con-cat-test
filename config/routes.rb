Rails.application.routes.draw do
  root "dashboard#show"
  resources :leads, only: :show

  get "/login", to: "sessions#new"
  post "/login", to: "sessions#create"
  delete "/logout", to: "sessions#destroy"

  namespace :admin do
    resources :pixels, only: %i[index create]
  end

  namespace :api do
    namespace :pixel do
      post "visit", to: "visits#create"
      post "interactions", to: "interactions#create"
      post "leads", to: "leads#create"
      get "leads/:id/activity", to: "leads#activity"
    end
  end

  get "/super-pixel.js", to: "pixel_assets#show"
  get "/certificates/:id/verify", to: "certificates#verify"
end
