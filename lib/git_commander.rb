require 'sinatra/base'

class DeployAbortedError < StandardError; end

module Sinatra

  module GitCommander
    def get_cmd(cmd, site)
      path = settings.sites[site]['path']
      env = settings.sites[site]['rails_env']
      %x[ cd #{path} && RAILS_ENV=#{env} #{cmd} ]
    end
    def run_cmd(cmd, site)
      path = settings.sites[site]['path']
      env = settings.sites[site]['rails_env']
      puts "<b>&gt; #{cmd}</b>"
      unless system("cd #{path} && RAILS_ENV=#{env} #{cmd}")
        raise DeployAbortedError
      end
    end

    module Helpers
      def git_branch(site)
        get_cmd('git rev-parse --abbrev-ref HEAD', site).strip
      end
      def git_status(site)
        get_cmd('git status --porcelain', site).strip
      end
      def git_origin(site)
        get_cmd('git config --get remote.origin.url', site).strip
      end
      def git_validate!(site)
        unless settings.sites[site]
          flash[:error] = "Invalid instance #{site}"
          redirect to('/')
        else
          path = settings.sites[site]['path']
          unless File.exists?("#{path}/.git")
            flash[:error] = "Invalid path #{path} for instance #{site}"
          end
        end
      end
      def git_checkout(branch, site)
        run_cmd("git checkout #{branch}", site)
        run_cmd("git pull", site)
      end

      # other commands
      def bundle_install(site)
        run_cmd("bundle install", site)
      end
      def rake_db_migrate(site)
        run_cmd("rake db:migrate", site)
      end
      def rake_assets_precompile(site)
        run_cmd("rake assets:precompile", site)
      end
      def rails_restart(site)
        run_cmd("touch tmp/restart.txt", site)
      end
    end

    def self.registered(app)
      app.helpers GitCommander::Helpers
    end

  end

  register GitCommander
end
