Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
  patch "projects/filters", to: "projects#filters", as: :project_filters
  resources :projects, only: %i[index show new create edit update], param: :uid do
    patch :command, on: :member
  end
  root "studio#show"
  get "apps/:page", to: "studio#show", as: :app
  patch "appearance", to: "studio#appearance"
  post "appearance/bootstrap", to: "studio#bootstrap"
end
