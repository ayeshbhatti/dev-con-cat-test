class SessionsController < ApplicationController
  def new
    redirect_to root_path if current_user
  end

  def create
    user = User.find_by("lower(email) = ?", params[:email].to_s.downcase.strip)
    if user&.authenticate(params[:password])
      reset_session
      session[:user_id] = user.id
      redirect_to root_path, notice: "Signed in."
    else
      flash.now[:alert] = "Email or password is incorrect."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Signed out."
  end
end
