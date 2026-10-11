class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: %i[new create]
  before_action :load_appearance, only: %i[new create]
  rate_limit to: 8, within: 3.minutes, only: :create,
    with: -> { redirect_to new_session_path, alert: "Muitas tentativas. Aguarde três minutos.", status: :see_other }

  def new
    redirect_to root_path if authenticated?
  end

  def create
    user = User.authenticate_by(email_address: params[:email_address].to_s.strip.downcase, password: params[:password].to_s)
    if user
      start_session(user)
      redirect_to root_path, status: :see_other
    else
      flash.now[:alert] = "E-mail ou senha inválidos."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    end_session
    redirect_to new_session_path, status: :see_other
  end

  private

  def load_appearance
    @appearance = Studio.appearance(cookies.encrypted[:accio_appearance])
  end
end
