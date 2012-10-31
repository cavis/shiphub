require 'sinatra'
require 'sinatra/flash'
require 'sinatra/config_file'
require 'sinatra/json'
require 'json'
require 'sinatra/reloader' if development?
require 'haml'
require 'octokit'
require 'rest_client'
require './lib/git_authenticator.rb'
require './lib/git_commander.rb'
enable :sessions

# configure
config_file 'config/sites.yml'
GH_REPO = settings.github[:repo_url].sub('https://github.com/', '')
LOG_DONE = "\nDeployment success."
LOG_FAIL = "\nDeployment failed."

# authenticator
before do
  @login = session[:login]
  @repo_url = settings.github[:repo_url]
end

# home page
get '/' do
  authorize!
  @client = Octokit::Client.new(:login => @login, :oauth_token => session[:oauth_token])

  @sites = {}
  settings.sites.each do |key, cfg|
    @sites[key] = cfg
    @sites[key]['branch'] = git_branch(key)
    @sites[key]['status'] = git_status(key)
    @sites[key]['origin'] = git_origin(key)

    # make sure each site has the configured origin
    remt = settings.github[:repo_url].downcase
    orig = @sites[key]['origin'].downcase
    unless orig.start_with?(remt) || orig.end_with?("#{GH_REPO}.git")
      flash[:error] = "Error - your #{cfg['name']} instance (#{orig}) doesn't match the configured ShipHub url"
    end
  end

  # most important -- can we access the site?
  begin
    @repo = @client.repo(GH_REPO)
  rescue
    flash[:error] = "FATAL - you don't seem to have access to #{GH_REPO}"
    redirect to('/error')
  end
  @branches = @client.branches(GH_REPO)
  @pullreqs = @client.pulls(GH_REPO)
  haml :home
end

# empty page to show fatal errors
get '/error' do
  haml :error
end

# progress indicator json
get '/instance/:instance' do
  log = "locks/#{params[:instance]}"
  file = File.exists?(log) ? File.read(log) : false
  locked = isLogLocked(log)
  content  = locked ? file : false
  previous = !locked ? file : false

  # NOTE - sinatra json fails to encode, so do it manually
  # json locked: locked, progress: content, previous: previous
  content_type :json
  { locked: locked, progress: content, previous: previous }.to_json
end

# branch deployer
def isLogLocked(path)
  if File.exists?(path)
    content = File.read(path)
    if !content.strip.empty? &&
       !(content.match /#{Regexp.escape(LOG_DONE)}$/) &&
       !(content.match /#{Regexp.escape(LOG_FAIL)}$/)
      return true
    end
  end
  false
end
post '/instance/:instance/branch/:name' do
  log = "locks/#{params[:instance]}"
  if isLogLocked(log)
    json success: false, message: 'Instance is locked'
  else
    log = File.path(log)
    start_msg = "#{Time.now}\n"
    start_msg += "Starting deploy of branch #{params[:name]}\n"
    File.open(log, 'w') {|f| f.write(start_msg)}

    # fork a child to run git commands in background
    fork do
      f = File.open(log, "a")
      STDOUT.reopen f
      STDERR.reopen f
      STDOUT.sync = true
      begin
        git_checkout(params[:name], params[:instance])
        bundle_install(params[:instance])
        rake_db_migrate(params[:instance])
        rake_assets_precompile(params[:instance])
        rails_restart(params[:instance])
        f.write("\n#{LOG_DONE}")
      rescue DeployAbortedError
        f.write("\n#{LOG_FAIL}")
      end
      f.close
      exit
    end
    json success: true, progress: start_msg
  end
end

post '/instance/:instance/pull/:number' do
  json :number => params[:number], :instance => params[:instance]
end
