Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
  root "studio#show"
  get "apps/:page", to: "studio#show", as: :app
  patch "appearance", to: "studio#appearance"
  post "appearance/bootstrap", to: "studio#bootstrap"
end
