require 'thin'
require 'renee'
require 'coderay'
require 'uri'
require 'haml'
require 'mimetype_fu'
require 'pygments'

module Gitdocs
  class Server
    def initialize(manager, *gitdocs)
      @manager = manager
      @gitdocs = gitdocs
    end

    def start(port = 8888)
      gds = @gitdocs
      manager = @manager

      Tilt.prefer ::MarkdownTemplate, 'md'
      Tilt.prefer ::MarkdownTemplate, 'mkd'
      Tilt.prefer ::MarkdownTemplate, 'markdown'

      Thin::Logging.debug = @manager.debug
      Thin::Server.start('127.0.0.1', port) do
        use Rack::Static, :urls => ['/css', '/js', '/img', '/doc'], :root => File.expand_path("../public", __FILE__)
        use Rack::MethodOverride
        run Renee {
          if request.path_info == '/'
            if manager.config.shares.size == 1
              redirect! "/0"
            else
              render! "home", :layout => 'app', :locals => {:conf => manager.config, :nav_state => "home" }
            end
          else
            path 'settings' do
              get.render! 'settings', :layout => 'app', :locals => {:conf => manager.config, :nav_state => "settings" }
              post do
                shares = manager.config.shares
                manager.config.global.update_attributes(request.POST['config'])
                request.POST['share'].each do |idx, share|
                  if remote_branch = share.delete('remote_branch')
                    share['remote_name'], share['branch_name'] = remote_branch.split('/', 2)
                  end
                  # Update paths
                  if share['path'] && !share['path'].empty?
                    shares[Integer(idx)].update_attributes(share)
                  end
                end
                EM.add_timer(0.1) { manager.restart }
                redirect! '/settings'
              end
            end

            path('search').get do
              render! "search", :layout => 'app', :locals => {:conf => manager.config, :results => manager.search(request.GET['q']), :nav_state => nil}
            end

            path('shares') do
              post do
                Configuration::Share.create
                redirect! '/settings'
              end

              var(:int) do |id|
                delete do
                  share = manager.config.shares.find { |s| s.id == id }
                  halt 404 if share.nil?
                  share.destroy
                  redirect! '/settings'
                end
              end
            end

            var :int do |idx|
              gd = gds[idx]
              halt 404 if gd.nil?
              file_path = URI.unescape(request.path_info)
              file_ext  = File.extname(file_path)
              expanded_path = File.expand_path(".#{file_path}", gd.root)
              message_file = File.expand_path(".gitmessage~", gd.root)
              halt 400 unless expanded_path[/^#{Regexp.quote(gd.root)}/]
              parent = File.dirname(file_path)
              parent = '' if parent == '/'
              parent = nil if parent == '.'
              locals = {:idx => idx, :parent => parent, :root => gd.root, :file_path => expanded_path, :nav_state => nil }
              mime = File.mime_type?(File.open(expanded_path)) if File.file?(expanded_path)
              mode = request.params['mode']
              if mode == 'meta' # Meta
                halt 200, { 'Content-Type' => 'application/json' }, [gd.file_meta(file_path).to_json]
              elsif mode == 'save' # Saving
                File.open(expanded_path, 'w') { |f| f.print request.params['data'] }
                File.open(message_file, 'w') { |f| f.print request.params['message'] } unless request.params['message'] == ''
                redirect! "/" + idx.to_s + file_path
              elsif mode == 'upload'  # Uploading
                halt 404 unless file = request.params['file']
                tempfile, filename = file[:tempfile], file[:filename]
                FileUtils.mv(tempfile.path, File.expand_path(filename, expanded_path))
                redirect! "/" + idx.to_s + file_path + "/" + filename
              elsif !File.exist?(expanded_path) && !request.params['dir'] # edit for non-existent file
                FileUtils.mkdir_p(File.dirname(expanded_path))
                FileUtils.touch(expanded_path)
                redirect!  "/" + idx.to_s + file_path + "?mode=edit"
              elsif !File.exist?(expanded_path) && request.params['dir'] # create directory
                FileUtils.mkdir_p(expanded_path)
                redirect!  "/" + idx.to_s + file_path
              elsif File.directory?(expanded_path) # list directory
                contents =  gd.dir_files(expanded_path)
                rendered_readme = nil
                if readme = Dir[File.expand_path("README.{md,txt}", expanded_path)].first
                  rendered_readme = '<h3>' + File.basename(readme) + '</h3><div class="tilt">' + render(readme) + '</div>'
                end
                render! "dir", :layout => 'app', :locals => locals.merge(:contents => contents, :rendered_readme => rendered_readme)
              elsif mode == "revisions" # list revisions
                revisions = gd.file_revisions(file_path)
                render! "revisions", :layout => 'app', :locals => locals.merge(:revisions => revisions)
              elsif mode == "revert" # revert file
                if revision = request.params['revision']
                  File.open(message_file, 'w') { |f| f.print "Reverting '#{file_path}' to #{revision}" }
                  gd.file_revert(file_path, revision)
                end
                redirect! "/" + idx.to_s + file_path
              elsif mode == 'delete' # delete file
                FileUtils.rm(expanded_path)
                redirect! "/" + idx.to_s + parent
              elsif mode == 'edit' && (mime.match(%r{text/}) || mime.match(%r{x-empty})) # edit file
                contents = File.read(expanded_path)
                render! "edit", :layout => 'app', :locals => locals.merge(:contents => contents)
              elsif mode != 'raw' # render file
                revision = request.params['revision']
                expanded_path = gd.file_revision_at(file_path, revision) if revision
                begin # attempting to render file
                  contents = '<div class="tilt">' + render(expanded_path) + '</div>'
                rescue RuntimeError => e # not tilt supported
                  contents = if mime.match(%r{text/})
                    '<pre class="CodeRay">' + CodeRay.scan_file(expanded_path).encode(:html) + '</pre>'
                  else
                    %|<embed class="inline-file" src="/#{idx}#{request.path_info}?mode=raw"></embed>|
                  end
                end
                render! "file", :layout => 'app', :locals => locals.merge(:contents => contents, 
                  :pygments_css => Pygments.css('.highlight'))
              else # other file
                run! Rack::File.new(gd.root)
              end
            end
          end
        }.setup {
          views_path File.expand_path("../views", __FILE__)
        }
      end
    end
  end
end
