require 'redcarpet'
require 'pygments'

# Singleton markdown converter, configured with github favoured markdown
# 
# adapted from  (https://github.com/chitsaou/ruby-taiwan/blob/d342b58dcfff3089a9599714a6911ca9c1f1490f/config/initializers/markdown.rb)
class MarkdownConverter
  include Singleton

  class HTMLwithSyntaxHighlight < Redcarpet::Render::HTML
    def block_code(code, language)
     language = 'text' if language.blank?
     begin
       Pygments.highlight(code, :lexer => language, :formatter => 'html', :options => {:encoding => 'utf-8'})
     rescue
       Pygments.highlight(code, :lexer => 'text', :formatter => 'html', :options => {:encoding => 'utf-8'})
     end
    end
  end

  def self.convert(text)
    self.instance.convert(text)
  end

  def convert(text)
    text = text.force_encoding('utf-8') if text.respond_to?(:force_encoding)
    @converter.render(text)
  end

  private
  def initialize
    html_renderer = HTMLwithSyntaxHighlight.new({
      :filter_html => true # filter out html tags
    })

    @converter = Redcarpet::Markdown.new(html_renderer, {
      :autolink => true,
      :fenced_code_blocks => true,
      :gh_blockcode => true,
      :hard_wrap => true,
      :no_intraemphasis => true
    })
  end
end
