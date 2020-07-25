require 'test_helper'

module UserService
  class UsersControllerTest < ActionDispatch::IntegrationTest
    include Engine.routes.url_helpers

    setup do
      @user = user_service_users(:one)
    end

    test "should get index" do
      get users_url, as: :json
      assert_response :success
    end

    test "should create user" do
      assert_difference('User.count') do
        post users_url, params: { user: { email: @user.email, roles: @user.roles } }, as: :json
      end

      assert_response 201
    end

    test "should show user" do
      get user_url(@user), as: :json
      assert_response :success
    end

    test "should update user" do
      patch user_url(@user), params: { user: { email: @user.email, roles: @user.roles } }, as: :json
      assert_response 200
    end

    test "should destroy user" do
      assert_difference('User.count', -1) do
        delete user_url(@user), as: :json
      end

      assert_response 204
    end
  end
end
