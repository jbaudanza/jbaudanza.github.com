require 'rubygems'
require 'bundler'

Bundler.require

require 'rack/lobster'
require 'rack/asset_compiler'
require 'rack/sass_compiler'

class HTMLwithPygments < Redcarpet::Render::HTML
  def block_code(code, language)
    Pygments.highlight(code, :lexer => language)
  end
end

template = Haml::Engine.new(File.read('haml/template.haml'))
markdown = Redcarpet::Markdown.new(HTMLwithPygments,
    :fenced_code_blocks => true)

use Rack::AssetCompiler,
  :source_dir => 'markdown',
  :url => '/',
  :content_type => 'text/html',
  :source_extension => 'md',
  :compiler => lambda { |source_file|
    template = Haml::Engine.new(File.read('haml/template.haml'))

    template.render do
      markdown.render(File.read(source_file))
    end
  }

use Rack::SassCompiler, :source_dir => 'sass', :url => '/css'

map '/pygments/' do
  run lambda{ |env|
    match = env['PATH_INFO'].match(/^\/(\w+)\.css$/)

    if match
      style = match[1]

      if Pygments.styles.include?(style)
        headers = {
          'Content-Type' => 'text/css',
          'Cache-Control' => 'public, max-age=604800' # 1 week
        }
        body = Pygments.css('.highlight', :style => style)
        return [200, headers, [body]]
      end
    end

    [404, {'Content-Type' => 'text/plain'}, ['Not found']]
  }
end

run Rack::Lobster.new