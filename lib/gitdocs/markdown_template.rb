require 'tilt/template'

class MarkdownTemplate < Tilt::Template
  self.default_mime_type = 'text/html'

  def initialize_engine
    require_template_library 'pygments'
  end

  def prepare
  end

  def self.engine_initialized?
    true
  end

  def evaluate(scope, locals, &block)
    @output ||= MarkdownConverter.convert(data)
  end
end