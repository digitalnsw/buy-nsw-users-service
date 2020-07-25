Rails.application.routes.draw do
  mount UserService::Engine => "/user_service"
end
