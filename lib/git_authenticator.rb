require 'sinatra/base'
require 'json'

module Sinatra
  module GitAuthenticator

    OAUTH_URL = 'https://github.com/login/oauth/authorize'
    TOKEN_URL = 'https://github.com/login/oauth/access_token'

    module Helpers
      def authorized?
        session[:oauth_token]
      end
      def authorize!
        redirect '/login' unless authorized?
      end
      def logout!
        session.clear
        flash[:notice] = 'You have been logged out'
        redirect to('/')
      end
    end

    def self.registered(app)
      app.helpers GitAuthenticator::Helpers

      # extra paths
      app.get '/login' do
        session[:oauth_token] = nil
        haml :login
      end
      app.get '/authorize' do
        if !params[:code]
          session[:my_state] = state = rand(36**8).to_s(36)
          id = settings.github[:app_id]
          redirect to("#{OAUTH_URL}?client_id=#{id}&state=#{state}&scope=repo,user")
        elsif params[:state] != session[:my_state]
          session.clear
          flash[:error] = 'There was a problem signing you into github'
          redirect to('/login')
        else
          args = {
            :client_id => settings.github[:app_id],
            :client_secret => settings.github[:app_secret],
            :code => params[:code],
            :state => params[:state]
          }

          # ask github for token
          RestClient.post(TOKEN_URL, args, :accept => :json) do |resp|
            if resp.code == 200 && json = ::JSON.parse(resp)
              if err = json['error']
                flash[:error] = "There was a problem signing you into github - #{err}"
                redirect to('/login')
              elsif tok = json['access_token']
                client = Octokit::Client.new(:oauth_token => tok)
                user = client.user()
                if user && user.login
                  if settings.github[:users].include?(user.login)
                    session[:login] = user.login
                    session[:oauth_token] = tok
                    flash[:notice] = "Successfully connected to github"
                    redirect to('/')
                  else
                    flash[:error] = "Woh there #{user.login}, you're not authorized to use this really, really neat app. You're totally missing out."
                    redirect to('/login')
                  end
                else
                  flash[:error] = "Unable to get user information from github"
                  redirect to('/login')
                end
              else
                flash[:error] = "Unknown error while authorizing github - #{resp}"
                redirect to('/login')
              end
            else
              flash[:error] = 'There was a problem signing you into github'
              redirect to('/login')
            end
          end
        end
      end
      app.get '/logout' do
        logout!
      end
    end
  end

  register GitAuthenticator
end
